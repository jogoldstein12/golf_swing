// Setup quality signals — the four live checklist chips that gate arming. This is what
// makes analysis accurate: a full-body, well-lit, upright, correctly-distanced capture
// is measurable; anything else produces numbers we'd have to apologize for.
import CoreMotion
import Foundation
import SwingKit

struct SetupChecklist: Equatable {
    enum Item: CaseIterable, Equatable {
        case body, distance, upright, light
        var label: String {
            switch self {
            case .body: "In frame"
            case .distance: "Distance"
            case .upright: "Upright"
            case .light: "Light"
            }
        }
    }

    var body = false
    var distance = false
    var upright = false
    var light = false

    var allSatisfied: Bool { body && distance && upright && light }
    func satisfied(_ item: Item) -> Bool {
        switch item {
        case .body: body
        case .distance: distance
        case .upright: upright
        case .light: light
        }
    }
}

/// Computes raw verdicts from a pose sample + motion tilt, then debounces each chip
/// (a flip requires the new verdict to hold for ~0.25s) so the row reads calm, not
/// jittery.
struct ChecklistEvaluator {
    // Full body: the joints a swing measurement cannot do without. One arm may
    // self-occlude down the line, so wrists/elbows require only one confident side.
    private static let core: [Joint] = [
        .neck, .pelvis, .shoulderL, .shoulderR,
        .hipL, .hipR, .kneeL, .kneeR, .ankleL, .ankleR,
    ]
    /// Safe-area margin: every joint at least this far inside each edge.
    private static let margin = 0.02
    /// Subject bbox height as a fraction of frame height. The band is wider than a
    /// standing-height rule because an addressed golfer is folded over — the fixture
    /// reads 0.53 at address and 0.66 standing, both correct distances.
    private static let heightBand = 0.50...0.88
    /// CoreMotion gravity within ~4° of portrait vertical (hysteresis to 7° once green).
    private static let uprightEnter = 4.0, uprightExit = 7.0
    private static let lumaEnter = 0.22, lumaExit = 0.17

    private var streaks: [SetupChecklist.Item: (verdict: Bool, count: Int)] = [:]
    private(set) var checklist = SetupChecklist()

    mutating func update(sample: LivePoseSample, tiltDegrees: Double?) -> SetupChecklist {
        let inFrame = Self.core.allSatisfy { joint in
            guard let p = sample.point(joint, min: 0.3) else { return false }
            return p.x > Self.margin && p.x < 1 - Self.margin
                && p.y > Self.margin && p.y < 1 - Self.margin
        }
        let armSeen = sample.point(.wristL, min: 0.3) != nil
            || sample.point(.wristR, min: 0.3) != nil
        apply(.body, raw: inFrame && armSeen)

        let height = sample.bbox?.height ?? 0
        apply(.distance, raw: Self.heightBand.contains(height))

        // Unmeasurable (Simulator / motion unavailable) counts as satisfied — the chip
        // can only ever help on hardware. Documented dev concession.
        let uprightRaw: Bool
        if let tiltDegrees {
            uprightRaw = tiltDegrees <= (checklist.upright ? Self.uprightExit
                                                          : Self.uprightEnter)
        } else {
            uprightRaw = true
        }
        apply(.upright, raw: uprightRaw)

        apply(.light, raw: sample.meanLuma >= (checklist.light ? Self.lumaExit
                                                               : Self.lumaEnter))
        return checklist
    }

    /// Debounce: 4 consecutive identical raw verdicts (~0.25s at 15Hz) to flip a chip.
    private mutating func apply(_ item: SetupChecklist.Item, raw: Bool) {
        guard raw != checklist.satisfied(item) else {
            streaks[item] = nil
            return
        }
        var streak = streaks[item] ?? (raw, 0)
        if streak.verdict != raw { streak = (raw, 0) }
        streak.count += 1
        if streak.count >= 4 {
            switch item {
            case .body: checklist.body = raw
            case .distance: checklist.distance = raw
            case .upright: checklist.upright = raw
            case .light: checklist.light = raw
            }
            streaks[item] = nil
        } else {
            streaks[item] = streak
        }
    }
}

/// Phone-upright signal. Gravity in the device frame should sit along −Y when the
/// phone stands in portrait; the published value is the angular error from that, in
/// degrees. nil = no motion hardware (Simulator).
final class MotionService {
    private let manager = CMMotionManager()
    private(set) var tiltDegrees: Double?

    func start() {
        guard manager.isDeviceMotionAvailable else {
            tiltDegrees = nil
            return
        }
        manager.deviceMotionUpdateInterval = 1.0 / 15.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let g = motion?.gravity else { return }
            let len = (g.x * g.x + g.y * g.y + g.z * g.z).squareRoot()
            guard len > 0 else { return }
            let cosine = max(-1, min(1, -g.y / len))
            self?.tiltDegrees = Foundation.acos(cosine) * 180 / .pi
        }
    }

    func stop() { manager.stopDeviceMotionUpdates() }
}
