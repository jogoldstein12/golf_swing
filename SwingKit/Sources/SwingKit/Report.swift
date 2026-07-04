// SwingReport — the single artifact the measurement layer produces and everything else
// consumes (analysis UI, 3D avatar, coaching, history). Coaching is grounded ONLY in
// what's in here: numbers first, words second.
import Foundation
import simd

public enum CaptureView: String, Codable, Sendable {
    case downTheLine, faceOn, fused
}

/// P-system checkpoints. p1 address … p7 impact … p10 finish.
public enum SwingPosition: Int, Codable, CaseIterable, Sendable, Comparable {
    case p1 = 1, p2, p3, p4, p5, p6, p7, p8, p9, p10
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    public var shortName: String { "P\(rawValue)" }
    public var name: String {
        switch self {
        case .p1: "Address"; case .p2: "Takeaway"; case .p3: "Lead Arm Parallel"
        case .p4: "Top"; case .p5: "Transition"; case .p6: "Delivery"
        case .p7: "Impact"; case .p8: "Release"; case .p9: "Follow-Through"
        case .p10: "Finish"
        }
    }
    /// The four headline checkpoints surfaced by default in the scrubber.
    public static let headline: [SwingPosition] = [.p1, .p4, .p7, .p10]
}

public struct CheckpointMark: Codable, Sendable {
    public var position: SwingPosition
    public var time: Double
    public var frameIndex: Int
    public init(position: SwingPosition, time: Double, frameIndex: Int) {
        self.position = position; self.time = time; self.frameIndex = frameIndex
    }
}

/// A measured quantity displayed against its ideal band.
public struct MetricValue: Codable, Sendable {
    public var label: String
    public var value: Double
    public var unit: String              // "°", ":1", "in", "s"
    public var idealLow: Double
    public var idealHigh: Double
    public var displayLow: Double        // meter range
    public var displayHigh: Double
    public var higherIsBetter: Bool?     // nil = band-centered

    public init(label: String, value: Double, unit: String,
                ideal: ClosedRange<Double>, display: ClosedRange<Double>,
                higherIsBetter: Bool? = nil) {
        self.label = label; self.value = value; self.unit = unit
        self.idealLow = ideal.lowerBound; self.idealHigh = ideal.upperBound
        self.displayLow = display.lowerBound; self.displayHigh = display.upperBound
        self.higherIsBetter = higherIsBetter
    }

    public var inBand: Bool { value >= idealLow && value <= idealHigh }
    public var fill: Double { // 0…1 position on the meter
        guard displayHigh > displayLow else { return 0 }
        return min(1, max(0, (value - displayLow) / (displayHigh - displayLow)))
    }
    public var bandFill: ClosedRange<Double> {
        guard displayHigh > displayLow else { return 0...0 }
        let a = min(1, max(0, (idealLow - displayLow) / (displayHigh - displayLow)))
        let b = min(1, max(0, (idealHigh - displayLow) / (displayHigh - displayLow)))
        return a...b
    }
}

/// Six degrees of freedom for one body segment (pelvis or chest), all vs address.
/// Angles in degrees, translations in inches (display convention from Sportsbox).
public struct SixDOF: Codable, Sendable {
    public var turn: Double, bend: Double, sideBend: Double
    public var sway: Double, lift: Double, thrust: Double
    public init(turn: Double = 0, bend: Double = 0, sideBend: Double = 0,
                sway: Double = 0, lift: Double = 0, thrust: Double = 0) {
        self.turn = turn; self.bend = bend; self.sideBend = sideBend
        self.sway = sway; self.lift = lift; self.thrust = thrust
    }
}

/// Kinematic sequence measurement: who peaked when, in what order.
public struct KinematicSequence: Codable, Sendable {
    public enum Segment: String, Codable, CaseIterable, Sendable {
        case pelvis, torso, leadArm, club   // club == grip proxy
    }
    public struct Peak: Codable, Sendable {
        public var segment: Segment
        public var time: Double             // seconds, downswing-relative
        public var peakDegPerSec: Double
        public init(segment: Segment, time: Double, peakDegPerSec: Double) {
            self.segment = segment; self.time = time; self.peakDegPerSec = peakDegPerSec
        }
    }
    public var peaks: [Peak]                // in temporal order
    public var idealOrder: [Segment] { [.pelvis, .torso, .leadArm, .club] }
    public var isInOrder: Bool {
        peaks.map(\.segment) == [Segment.pelvis, .torso, .leadArm, .club]
    }
    /// Angular-velocity traces for the sequence graph (deg/s), sampled at `times`.
    public var times: [Double]
    public var series: [Segment: [Double]]
    public init(peaks: [Peak], times: [Double] = [], series: [Segment: [Double]] = [:]) {
        self.peaks = peaks; self.times = times; self.series = series
    }
}

/// Swing-plane measurement (down-the-line). Signed deviations: + is steep/above the
/// base plane (over the top), − is shallow/under.
public struct PlaneAnalysis: Codable, Sendable {
    /// How the base plane line was obtained. nil = plane analysis unavailable
    /// (shaft and ball detection both failed their quality gates, or face-on view);
    /// deviations are then empty — a missing plane is never invented.
    public enum Basis: String, Codable, Sendable {
        case shaftDetected      // shaft line found in the address video frame
        case gripBallLine       // fallback: address grip → detected ball
    }
    public var basePlaneAngle: Double            // deg from horizontal, address shaft plane
    public var deviationByPosition: [SwingPosition: Double]  // grip-path deviation, deg
    public var stateByPosition: [SwingPosition: PlaneState]
    /// The base plane line in normalized image space (top-left origin), for drawing
    /// directly over the video: [ground/ball end, upper end]. nil when the shaft
    /// couldn't be measured (never fabricate it).
    public var basePlaneLine2D: [SIMD2<Double>]?
    public var basis: Basis?
    /// 3D cross-check: inclination of the downswing grip-path plane minus the
    /// backswing grip-path plane (deg, + = downswing steeper, an over-the-top
    /// signature). From grip3 in the yaw-stabilized frame; lower trust than the
    /// 2D image-space numbers (see VALIDATION.md).
    public var planeShift3D: Double?
    public init(basePlaneAngle: Double,
                deviationByPosition: [SwingPosition: Double],
                stateByPosition: [SwingPosition: PlaneState],
                basePlaneLine2D: [SIMD2<Double>]? = nil,
                basis: Basis? = nil,
                planeShift3D: Double? = nil) {
        self.basePlaneAngle = basePlaneAngle
        self.deviationByPosition = deviationByPosition
        self.stateByPosition = stateByPosition
        self.basePlaneLine2D = basePlaneLine2D
        self.basis = basis
        self.planeShift3D = planeShift3D
    }
}

public enum Handedness: String, Codable, Sendable {
    case right, left
    /// The target-side (lead) arm: left for a right-handed golfer.
    public var leadIsLeft: Bool { self == .right }
}

public enum PlaneState: String, Codable, Sendable {
    case on, over, under, neutral
}

public enum MarkerKind: String, Codable, Sendable { case good, fault }

/// A tappable annotation pinned to a joint at a checkpoint.
public struct SwingMarker: Codable, Identifiable, Sendable {
    public var id: String
    public var position: SwingPosition
    public var joint: Joint
    public var kind: MarkerKind
    public var title: String
    public var detail: String
    public init(id: String, position: SwingPosition, joint: Joint, kind: MarkerKind,
                title: String, detail: String) {
        self.id = id; self.position = position; self.joint = joint; self.kind = kind
        self.title = title; self.detail = detail
    }
}

public struct SwingScore: Codable, Sendable {
    public struct Component: Codable, Sendable {
        public var label: String
        public var score: Double     // 0…1
        public var weight: Double
        public init(label: String, score: Double, weight: Double) {
            self.label = label; self.score = score; self.weight = weight
        }
    }
    public var total: Int            // 0…100
    public var components: [Component]
    public init(total: Int, components: [Component]) {
        self.total = total; self.components = components
    }
}

// MARK: - Coaching (interpretation layer output)

public struct CoachGoal: Codable, Identifiable, Sendable {
    public var id: String { title }
    public var priority: Int
    public var title: String
    public var detail: String
    public var metricLabel: String
    public var current: String
    public var target: String
    public var drill: String
    public var drillDetail: String
    public init(priority: Int, title: String, detail: String, metricLabel: String,
                current: String, target: String, drill: String, drillDetail: String) {
        self.priority = priority; self.title = title; self.detail = detail
        self.metricLabel = metricLabel; self.current = current; self.target = target
        self.drill = drill; self.drillDetail = drillDetail
    }
}

public enum CoachingSource: String, Codable, Sendable { case claude, rules }

public struct CoachingPlan: Codable, Sendable {
    public var verdict: String           // one-line editorial pull-quote
    public var goals: [CoachGoal]        // priority-ordered, earliest chain link first
    public var source: CoachingSource
    public init(verdict: String, goals: [CoachGoal], source: CoachingSource) {
        self.verdict = verdict; self.goals = goals; self.source = source
    }
}

// MARK: - The report

public struct SwingReport: Codable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    public var club: String
    public var view: CaptureView
    public var videoFileName: String?    // relative to the app's swings directory
    public var duration: Double
    public var frameRate: Double

    public var frames: [PoseFrame]
    public var checkpoints: [CheckpointMark]
    public var plane: PlaneAnalysis
    public var sequence: KinematicSequence
    public var pelvisDOF: [SwingPosition: SixDOF]
    public var chestDOF: [SwingPosition: SixDOF]
    public var metrics: [MetricValue]
    public var markers: [SwingMarker]
    public var score: SwingScore
    public var coaching: CoachingPlan?
    // Optional post-v1 additions (JSON-compatible: absent in old fixtures).
    /// Detected automatically from the tracks (wrist stacking at address + trail-elbow
    /// fold at the top). nil only for legacy reports.
    public var handedness: Handedness?
    /// The analyzed window in the source video's own timeline. `frames[].time` and
    /// checkpoint times are source-video times inside this window.
    public var windowStart: Double?
    public var windowEnd: Double?
    /// Source video pixel dimensions (orientation applied) — overlays need the aspect.
    public var videoWidth: Double?
    public var videoHeight: Double?

    public init(id: UUID = UUID(), date: Date = .init(), club: String, view: CaptureView,
                videoFileName: String? = nil, duration: Double, frameRate: Double,
                frames: [PoseFrame], checkpoints: [CheckpointMark], plane: PlaneAnalysis,
                sequence: KinematicSequence,
                pelvisDOF: [SwingPosition: SixDOF], chestDOF: [SwingPosition: SixDOF],
                metrics: [MetricValue], markers: [SwingMarker], score: SwingScore,
                coaching: CoachingPlan? = nil,
                handedness: Handedness? = nil,
                windowStart: Double? = nil, windowEnd: Double? = nil,
                videoWidth: Double? = nil, videoHeight: Double? = nil) {
        self.id = id; self.date = date; self.club = club; self.view = view
        self.videoFileName = videoFileName; self.duration = duration; self.frameRate = frameRate
        self.frames = frames; self.checkpoints = checkpoints; self.plane = plane
        self.sequence = sequence; self.pelvisDOF = pelvisDOF; self.chestDOF = chestDOF
        self.metrics = metrics; self.markers = markers; self.score = score
        self.coaching = coaching
        self.handedness = handedness
        self.windowStart = windowStart; self.windowEnd = windowEnd
        self.videoWidth = videoWidth; self.videoHeight = videoHeight
    }

    public func mark(_ p: SwingPosition) -> CheckpointMark? {
        checkpoints.first { $0.position == p }
    }
    public func frame(at time: Double) -> PoseFrame? {
        guard !frames.isEmpty else { return nil }
        var best = frames[0]
        for f in frames where abs(f.time - time) < abs(best.time - time) { best = f }
        return best
    }
}
