// Orchestration: one object owns the feed (camera or file, chosen by ST_FEED), the
// live pose loop, the motion signal, the checklist, and the swing detector, and turns
// their events into published UI state + recording side effects. All published
// mutations happen on the main actor; frames flow on background queues.
import AVFoundation
import Combine
import CoreGraphics
import Foundation
import SwiftUI
import SwingKit
import simd

struct CaptureTake: Equatable {
    let url: URL
    let view: CaptureView
    let fps: Double
    let duration: Double
}

@MainActor
final class CaptureController: ObservableObject {
    enum Screen: Equatable {
        case starting
        case live                    // setup / armed / capturing
        case review(CaptureTake)
        case denied                  // camera permission — designed empty state
        case unavailable(String)     // no feed (Simulator without ST_FEED=file)
    }

    @Published private(set) var screen: Screen = .starting
    @Published private(set) var phase: SwingDetector.Phase = .idle(hold: 0)
    @Published private(set) var checklist = SetupChecklist()
    @Published private(set) var angle: CaptureView = .downTheLine
    @Published private(set) var countdown: Int?
    @Published private(set) var exporting = false
    @Published private(set) var cue = "Fill the guide, then hold your address."
    /// Display-smoothed joints for the skeleton overlay (normalized, top-left origin).
    @Published private(set) var displayJoints: [Joint: SIMD2<Double>] = [:]

    var feedAspect: CGFloat { feed?.info.aspect ?? 9.0 / 16.0 }
    var feedFPS: Double { feed?.info.fps ?? 0 }
    let previewSink = PreviewSink()

    private var feed: CaptureFeed?
    private let pose = LivePoseService()
    private let motion = MotionService()
    private var evaluator = ChecklistEvaluator()
    private let detector = SwingDetector()
    private var cueExpiry: Date?
    private var countdownTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?
    private var exportGeneration = 0
    private var manualPending = false

    // MARK: - Lifecycle

    func start() {
        guard case .starting = screen else { return }
        let env = ProcessInfo.processInfo.environment
        let feed: CaptureFeed
        if env["ST_FEED"] == "file" {
            guard let url = Bundle.main.url(forResource: "sample_dtl", withExtension: "mp4") else {
                screen = .unavailable("sample_dtl.mp4 missing from bundle")
                return
            }
            feed = FileFeed(url: url)
            // Harness resilience: if this Simulator runtime can't run the body-pose
            // model, the pose loop falls back to the fixture's precomputed tracks.
            if let tracksURL = Bundle.main.url(forResource: "sample_dtl_tracks",
                                               withExtension: "json"),
               let data = try? Data(contentsOf: tracksURL),
               let tracks = try? JSONDecoder().decode([PoseFrame].self, from: data) {
                pose.fixtureTracks = tracks.sorted { $0.time < $1.time }
            }
        } else {
            feed = CameraFeed()
        }
        self.feed = feed
        feed.onFrame = { [weak self] frame in
            guard let self else { return }
            self.previewSink.enqueue(frame.sample)
            self.pose.submit(frame)
        }
        pose.onSample = { [weak self] sample in
            guard let self else { return }
            if self.consumeManualStart(sample) { return }
            self.consume(sample)
        }
        motion.start()

        Task {
            let availability = await feed.start()
            self.pose.orientation = feed.info.orientation
            withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
                switch availability {
                case .running: self.screen = .live
                case .denied: self.screen = .denied
                case .unavailable(let why): self.screen = .unavailable(why)
                }
            }
        }
    }

    func stopFeed() {
        countdownTask?.cancel()
        motion.stop()
        feed?.stop()
    }

    func restart() {
        stopFeed()
        feed = nil
        screen = .starting
        phase = .idle(hold: 0)
        checklist = SetupChecklist()
        displayJoints = [:]
        start()
    }

    func setAngle(_ new: CaptureView) {
        guard new != angle else { return }
        angle = new
        resetToIdle()
    }

    // MARK: - Pose consumption

    private func consume(_ sample: LivePoseSample) {
        guard case .live = screen, countdown == nil, !exporting,
              detectorActive else { updateSkeleton(sample); return }

        checklist = evaluator.update(sample: sample, tiltDegrees: motion.tiltDegrees)

        let input = SwingDetector.Input(
            time: sample.time,
            sourceTime: sample.sourceTime,
            grip: sample.grip,
            hipCenterX: hipCenterX(sample),
            spineFromVerticalDeg: spineAngle(sample),
            checklistGreen: checklist.allSatisfied,
            requirePosture: angle == .downTheLine)

        let events = detector.ingest(input)
        if debugDetector {
            NSLog("DET t=%.2f src=%.2f v=%.3f phase=%@ chips=%d",
                  sample.time, sample.sourceTime, detector.gripSpeed,
                  String(describing: detector.phase), checklist.allSatisfied ? 1 : 0)
            for e in events { NSLog("DET   event %@", String(describing: e)) }
        }
        applyPhase(detector.phase)
        for event in events { handle(event, at: sample) }
        updateSkeleton(sample)
        refreshCue()
    }

    private let debugDetector =
        ProcessInfo.processInfo.environment["ST_LOG_DETECT"] == "1"

    private var detectorActive: Bool {
        if case .captured = detector.phase { return false }
        return true
    }

    /// Locomotion signal for the walk-off rule: pelvis x, else hip midpoint.
    private func hipCenterX(_ sample: LivePoseSample) -> Double? {
        if let p = sample.point(.pelvis) { return p.x }
        guard let l = sample.point(.hipL), let r = sample.point(.hipR) else { return nil }
        return (l.x + r.x) * 0.5
    }

    /// Spine lean from vertical in degrees, aspect-corrected so the angle is physical,
    /// not a normalized-coordinate artifact. Hip midpoint → shoulder midpoint.
    private func spineAngle(_ sample: LivePoseSample) -> Double? {
        guard let hl = sample.point(.hipL), let hr = sample.point(.hipR),
              let sl = sample.point(.shoulderL), let sr = sample.point(.shoulderR)
        else { return nil }
        let hip = (hl + hr) * 0.5, shoulder = (sl + sr) * 0.5
        let dx = (shoulder.x - hip.x) * Double(feedAspect)  // width units → height units
        let dy = hip.y - shoulder.y                         // up is positive
        guard dy > 0.01 else { return 90 }
        return atan2(abs(dx), dy) * 180 / .pi
    }

    private func updateSkeleton(_ sample: LivePoseSample) {
        let showing: Bool = switch phase {
        case .ready, .capturing, .settling: true
        default: false
        }
        guard showing else {
            if !displayJoints.isEmpty { displayJoints = [:] }
            return
        }
        var next = displayJoints
        for (joint, p) in sample.joints where (sample.confidence[joint] ?? 0) >= 0.25 {
            next[joint] = next[joint].map { $0 + 0.55 * (p - $0) } ?? p
        }
        for joint in next.keys where sample.joints[joint] == nil {
            next.removeValue(forKey: joint)
        }
        displayJoints = next
    }

    // MARK: - Detector events → side effects

    private func applyPhase(_ new: SwingDetector.Phase) {
        guard new != phase else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { phase = new }
    }

    private func handle(_ event: SwingDetector.Event, at sample: LivePoseSample) {
        switch event {
        case .recordStart:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            feed?.beginTake()
        case .recordCancel:
            feed?.cancelTake()
        case .armed:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .triggered:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .disarmed(let reason):
            transientCue(for: reason)
        case .captured(let from, let to):
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            finishCapture(trimFrom: from, trimTo: to)
        }
    }

    private func finishCapture(trimFrom: Double, trimTo: Double) {
        guard let feed else { return }
        exporting = true
        exportTask?.cancel()
        exportGeneration += 1
        let generation = exportGeneration
        let takeAngle = angle
        let fps = feed.info.fps
        exportTask = Task {
            do {
                let url = try await feed.finishTake(fromSource: trimFrom, toSource: trimTo)
                guard !Task.isCancelled, generation == self.exportGeneration else {
                    try? FileManager.default.removeItem(at: url)
                    return
                }
                let duration = (try? await AVURLAsset(url: url).load(.duration).seconds)
                    ?? (trimTo - trimFrom)
                let take = CaptureTake(url: url, view: takeAngle,
                                       fps: fps, duration: duration)
                self.exportTask = nil
                self.exporting = false
                withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) {
                    self.screen = .review(take)
                }
            } catch {
                guard generation == self.exportGeneration else { return }
                self.exportTask = nil
                self.exporting = false
                self.cue = "Couldn't save that one — set up and swing again."
                self.cueExpiry = Date().addingTimeInterval(3)
                self.resetToIdle()
            }
        }
    }

    // MARK: - Review actions

    func retake() {
        if case .review(let take) = screen {
            try? FileManager.default.removeItem(at: take.url)
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.88)) {
            screen = .live
        }
        resetToIdle()
    }

    func discardUnacceptedTake() {
        exportGeneration += 1
        exportTask?.cancel()
        exportTask = nil
        exporting = false
        if case .review(let take) = screen {
            try? FileManager.default.removeItem(at: take.url)
            screen = .live
        }
    }

    func accept(onCaptured: (URL, CaptureView) -> Void) {
        guard case .review(let take) = screen else { return }
        NSLog("CaptureController: accepted %@ (%@, %.0f fps, %.1fs)",
              take.url.lastPathComponent, take.view.rawValue, take.fps, take.duration)
        onCaptured(take.url, take.view)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.88)) {
            screen = .live
        }
        cue = "Sent to analysis."
        cueExpiry = Date().addingTimeInterval(2.5)
        resetToIdle()
    }

    // MARK: - Manual countdown fallback

    func beginCountdown() {
        guard countdown == nil, case .live = screen, !exporting else { return }
        resetToIdle()
        countdownTask = Task {
            for n in [3, 2, 1] {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    self.countdown = n
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
            }
            withAnimation(.easeOut(duration: 0.25)) { self.countdown = nil }
            self.manualPending = true
            self.feed?.beginTake()
            self.cue = "Recording — swing away."
        }
    }

    func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        withAnimation(.easeOut(duration: 0.2)) { countdown = nil }
        resetToIdle()
    }

    /// Manual capture arms on the first pose sample after the countdown, which carries
    /// the source timestamp the trim needs.
    private func consumeManualStart(_ sample: LivePoseSample) -> Bool {
        guard manualPending else { return false }
        manualPending = false
        let input = SwingDetector.Input(
            time: sample.time, sourceTime: sample.sourceTime, grip: sample.grip,
            hipCenterX: nil, spineFromVerticalDeg: nil,
            checklistGreen: true, requirePosture: false)
        for event in detector.beginManualCapture(input: input) {
            handle(event, at: sample)
        }
        applyPhase(detector.phase)
        return true
    }

    private func resetToIdle() {
        detector.reset()
        evaluator = ChecklistEvaluator()
        feed?.cancelTake()
        applyPhase(.idle(hold: 0))
        displayJoints = [:]
    }

    // MARK: - Cue copy

    private func transientCue(for reason: SwingDetector.DisarmReason) {
        let text: String? = switch reason {
        case .posture: "Bend into your address — you're standing tall."
        case .walking: "Settle into the frame and hold still."
        case .lost: "Lost you — step back into the guide."
        case .timeout: "Re-armed. Hold your address when you're ready."
        case .checklist, .sceneCut: nil
        }
        if let text {
            cue = text
            cueExpiry = Date().addingTimeInterval(2.5)
        }
    }

    private func refreshCue() {
        if let expiry = cueExpiry {
            if Date() < expiry { return }
            cueExpiry = nil
        }
        let text: String
        switch phase {
        case .idle(let hold):
            if !checklist.allSatisfied {
                text = "Fill the guide, then hold your address."
            } else if hold > 0 {
                text = "Hold your address…"
            } else {
                text = "Checks green — hold your address to arm."
            }
        case .ready: text = "Armed. Swing when ready."
        case .capturing: text = "Capturing — swing away."
        case .settling: text = "Hold your finish…"
        case .captured: text = "Got it."
        }
        if text != cue { cue = text }
    }
}
