// The orchestrator: video in, SwingReport out. Same pipeline on macOS (swingctl) and
// iOS (the app) — this is the whole point of SwingKit being a package.
//
//   fast downscaled 2D pass (whole clip) -> find the swing window
//     -> full 2D+3D extraction on that window (+/- ~1s margin)
//     -> smooth -> checkpoints/tempo/handedness -> plane -> 6DOF -> kinematic sequence
//     -> metrics/score/markers -> SwingReport
//
// `report.frames` is the analyzed window only, at native fps; checkpoint times and
// frame times are in the source video's own timeline. `club`/`videoFileName` are left
// for the caller to set (the analyzer has no way to know either).
import Foundation

public enum SwingAnalyzer {
    public static func analyze(url: URL, view: CaptureView,
                               progress: ((Double) -> Void)? = nil) async throws -> SwingReport {
        // 1. Fast, downscaled, 2D-only pass over the whole clip to find the window.
        let coarse = try await PoseExtractor().extract(
            from: url, options: .init(include3D: false, downscale: 0.4)
        ) { p in progress?(p * 0.25) }
        let window = findWindow(frames: coarse.frames, duration: coarse.duration)

        // 2. Full 2D+3D extraction, on the window only.
        let full = try await PoseExtractor().extract(
            from: url, options: .init(window: window)
        ) { p in progress?(0.25 + p * 0.5) }
        guard full.frames.count > 8 else {
            throw NSError(domain: "SwingKit", code: 10,
                          userInfo: [NSLocalizedDescriptionKey: "not enough tracked frames in the detected swing window"])
        }

        // 3. Smooth.
        let smoothed = Smoothing.smooth(full.frames)
        progress?(0.80)

        // 4. Checkpoints, tempo, handedness.
        guard let timing = CheckpointDetector.detect(frames: smoothed) else {
            throw NSError(domain: "SwingKit", code: 11,
                          userInfo: [NSLocalizedDescriptionKey: "could not detect swing checkpoints in this clip"])
        }
        progress?(0.85)

        // 5. Swing plane (down-the-line only; empty/neutral for face-on).
        let plane = await SwingPlaneAnalyzer.analyze(frames: smoothed, timing: timing, view: view, videoURL: url)
        progress?(0.90)

        // 6. 6DOF, 7. kinematic sequence.
        let dof = SixDOFAnalyzer.analyze(frames: smoothed, timing: timing, view: view)
        let sequence = KinematicSequenceAnalyzer.analyze(frames: smoothed, timing: timing)
        progress?(0.95)

        // 8. Metrics, score, markers.
        let inputs = MetricsBuilder.Inputs(view: view, frames: smoothed, timing: timing, plane: plane,
                                           pelvisDOF: dof.pelvis, chestDOF: dof.chest, sequence: sequence)
        let metrics = MetricsBuilder.metrics(inputs)
        let score = MetricsBuilder.score(inputs, metrics: metrics)
        let markers = MetricsBuilder.markers(inputs)
        progress?(1.0)

        return SwingReport(
            club: "Unknown", view: view, videoFileName: nil,
            duration: full.duration, frameRate: full.nativeFPS,
            frames: smoothed, checkpoints: timing.checkpoints, plane: plane, sequence: sequence,
            pelvisDOF: dof.pelvis, chestDOF: dof.chest, metrics: metrics, markers: markers, score: score,
            handedness: timing.handedness, windowStart: window.lowerBound, windowEnd: window.upperBound,
            videoWidth: Double(full.videoSize.width), videoHeight: Double(full.videoSize.height))
    }

    /// Coarse address-to-finish window from the whole-clip fast pass: the first
    /// sustained stillness run's end (address, minus a margin) to the last sustained
    /// stillness run's start (finish, plus a margin) — same "genuine stillness, not
    /// a mid-swing pause" logic as CheckpointDetector's P1/P10 anchors, just looser
    /// (this only needs to bound the real extraction generously).
    private static func findWindow(frames: [PoseFrame], duration: Double) -> ClosedRange<Double> {
        let margin = 1.0
        let smoothed = Smoothing.smooth(frames)
        guard let motion = Motion.gripSpeed2D(smoothed) else { return 0...duration }
        let (times, _, speed) = motion
        guard !times.isEmpty else { return 0...duration }
        let stillRuns = Motion.quietRuns(times: times, speed: speed, threshold: 0.12, minDuration: 0.4)
        guard let first = stillRuns.first else { return 0...duration }
        let start = max(0, times[first.endIndex] - margin)
        let end: Double
        if let last = stillRuns.last, last.startIndex > first.endIndex + 4 {
            end = min(duration, times[last.startIndex] + margin)
        } else {
            end = duration
        }
        guard end > start + 0.5 else { return 0...duration } // sanity floor: never hand back a degenerate window
        return start...end
    }
}
