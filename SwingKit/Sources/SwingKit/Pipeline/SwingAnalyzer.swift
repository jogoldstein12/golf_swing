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
import AVFoundation
import Foundation
import os

public struct SwingAnalysisResult: Sendable {
    public var report: SwingReport
    public var diagnostics: AnalysisDiagnostics

    public init(report: SwingReport, diagnostics: AnalysisDiagnostics) {
        self.report = report
        self.diagnostics = diagnostics
    }
}

public struct SwingAnalysisFailure: LocalizedError, Sendable {
    public var diagnostics: AnalysisDiagnostics
    private var message: String

    public init(message: String, diagnostics: AnalysisDiagnostics) {
        self.message = message
        self.diagnostics = diagnostics
    }

    public var errorDescription: String? { message }
}

public enum SwingAnalyzer {
    private static let performanceLog = OSLog(
        subsystem: "com.swingthrough.SwingKit",
        category: "Analysis"
    )

    public static func analyze(url: URL, view: CaptureView,
                               sourceWindow: ClosedRange<Double>? = nil,
                               handednessOverride: Handedness? = nil,
                               progress: ((Double) -> Void)? = nil) async throws -> SwingReport {
        try await analyzeWithDiagnostics(
            url: url, view: view, sourceWindow: sourceWindow,
            handednessOverride: handednessOverride, progress: progress
        ).report
    }

    /// Diagnostic variant used by the app and device benchmark tooling. The callback
    /// receives privacy-safe snapshots at stage boundaries, including on failure.
    public static func analyzeWithDiagnostics(
        url: URL,
        view: CaptureView,
        sourceWindow: ClosedRange<Double>? = nil,
        handednessOverride: Handedness? = nil,
        jobID: UUID = UUID(),
        diagnostics onDiagnostics: ((AnalysisDiagnostics) -> Void)? = nil,
        progress: ((Double) -> Void)? = nil
    ) async throws -> SwingAnalysisResult {
        var diagnostics = AnalysisDiagnostics(jobID: jobID)
        diagnostics.recordThermalState()
        diagnostics.recordPeakMemory(AnalysisMemory.residentBytes())
        onDiagnostics?(diagnostics)

        do {
            let metadata = try await measured(
                "Preflight", key: "preflight", jobID: jobID, diagnostics: &diagnostics
            ) {
                try await sourceMetadata(for: url)
            }
            diagnostics.sourceDuration = metadata.duration
            diagnostics.sourceFPS = metadata.fps
            diagnostics.sourceWidth = Int(metadata.displaySize.width.rounded())
            diagnostics.sourceHeight = Int(metadata.displaySize.height.rounded())
            captureBoundary(&diagnostics, callback: onDiagnostics)

            let requestedWindow = normalizedWindow(sourceWindow, duration: metadata.duration)

        // 1. Fast, downscaled, 2D-only pass over the user-selected clip to find the window.
            let coarse = try await measured(
                "CoarsePose", key: "coarsePose", jobID: jobID, diagnostics: &diagnostics
            ) {
                try await PoseExtractor().extract(
                    from: url,
                    options: .init(
                        window: requestedWindow,
                        sampleFPS: 12,
                        include3D: false,
                        maximumDimension: 720
                    )
                ) { p in progress?(p * 0.25) }
            }
            diagnostics.sampled2DFrames += coarse.frames.count
            diagnostics.droppedFrames += max(0, coarse.attemptedSamples - coarse.frames.count)
            diagnostics.recoverableFrameErrors += coarse.recoverableFrameErrors
            captureBoundary(&diagnostics, callback: onDiagnostics)

            let window = try await measured(
                "DetectSwing", key: "detectSwing", jobID: jobID, diagnostics: &diagnostics
            ) {
                findWindow(frames: coarse.frames, bounds: requestedWindow)
            }
            captureBoundary(&diagnostics, callback: onDiagnostics)

        // 2. Full 2D+3D extraction, on the window only.
            let full = try await measured(
                "DetailedPose", key: "detailedPose", jobID: jobID, diagnostics: &diagnostics
            ) {
                try await PoseExtractor().extract(
                    from: url,
                    options: .init(window: window, sampleFPS: 30, maximumDimension: 960)
                ) { p in progress?(0.25 + p * 0.5) }
            }
            diagnostics.sampled2DFrames += full.frames.filter { !$0.j2.isEmpty }.count
            diagnostics.sampled3DFrames += full.frames.filter { !$0.j3.isEmpty }.count
            diagnostics.droppedFrames += max(0, full.attemptedSamples - full.frames.count)
            diagnostics.recoverableFrameErrors += full.recoverableFrameErrors
            captureBoundary(&diagnostics, callback: onDiagnostics)
            guard full.frames.count > 8 else {
                throw NSError(domain: "SwingKit", code: 10,
                              userInfo: [NSLocalizedDescriptionKey: "not enough tracked frames in the detected swing window"])
            }

        // 3. Smooth.
            let smoothed = try await measured(
                "Smoothing", key: "smoothing", jobID: jobID, diagnostics: &diagnostics
            ) {
                Smoothing.smooth(full.frames)
            }
            progress?(0.80)
            captureBoundary(&diagnostics, callback: onDiagnostics)

        // 4. Checkpoints, tempo, handedness.
            let timing = try await measured(
                "Checkpoints", key: "checkpoints", jobID: jobID, diagnostics: &diagnostics
            ) {
                guard let value = CheckpointDetector.detect(
                    frames: smoothed, handedness: handednessOverride
                ) else {
                    throw NSError(domain: "SwingKit", code: 11,
                                  userInfo: [NSLocalizedDescriptionKey: "could not detect swing checkpoints in this clip"])
                }
                return value
            }
            progress?(0.85)
            captureBoundary(&diagnostics, callback: onDiagnostics)

        // 5. Swing plane (down-the-line only; empty/neutral for face-on).
            let plane = try await measured(
                "SwingPlane", key: "swingPlane", jobID: jobID, diagnostics: &diagnostics
            ) {
                try await SwingPlaneAnalyzer.analyze(
                    frames: smoothed, timing: timing, view: view, videoURL: url
                )
            }
            progress?(0.90)
            captureBoundary(&diagnostics, callback: onDiagnostics)

        // 6. 6DOF, 7. kinematic sequence.
            let measurements = try await measured(
                "Measurements", key: "measurements", jobID: jobID, diagnostics: &diagnostics
            ) {
                let dof = SixDOFAnalyzer.analyze(frames: smoothed, timing: timing, view: view)
                let sequence = KinematicSequenceAnalyzer.analyze(frames: smoothed, timing: timing)
                return (dof, sequence)
            }
            progress?(0.95)
            captureBoundary(&diagnostics, callback: onDiagnostics)

        // 8. Metrics, score, markers.
            let report = try await measured(
                "Metrics", key: "metrics", jobID: jobID, diagnostics: &diagnostics
            ) {
                let inputs = MetricsBuilder.Inputs(
                    view: view, frames: smoothed, timing: timing, plane: plane,
                    pelvisDOF: measurements.0.pelvis, chestDOF: measurements.0.chest,
                    sequence: measurements.1
                )
                let baseQuality = MetricsBuilder.reportQuality(inputs)
                let baseMetrics = MetricsBuilder.metrics(inputs)
                // A1: withhold anatomically impossible measurements and, when the
                // 3D-rotation family is degenerate, collapse orientation confidence so
                // the score gate below responds (the A0 fix).
                let gated = PlausibilityGate.apply(metrics: baseMetrics, quality: baseQuality)
                let quality = gated.quality
                let metrics = gated.metrics
                let score = MetricsBuilder.score(inputs, metrics: metrics, quality: quality)
                let markers = MetricsBuilder.markers(inputs)
                return SwingReport(
                    club: "Unknown", view: view, videoFileName: nil,
                    duration: full.duration, frameRate: full.nativeFPS,
                    frames: smoothed, checkpoints: timing.checkpoints, plane: plane,
                    sequence: measurements.1, pelvisDOF: measurements.0.pelvis,
                    chestDOF: measurements.0.chest, metrics: metrics, markers: markers,
                    score: score, handedness: timing.handedness,
                    windowStart: window.lowerBound, windowEnd: window.upperBound,
                    videoWidth: Double(full.videoSize.width), videoHeight: Double(full.videoSize.height),
                    schemaVersion: 2, quality: quality
                )
            }
            progress?(1.0)
            diagnostics.finish()
            captureBoundary(&diagnostics, callback: onDiagnostics)
            return SwingAnalysisResult(report: report, diagnostics: diagnostics)
        } catch {
            diagnostics.recordFailure(error)
            captureBoundary(&diagnostics, callback: onDiagnostics)
            if error is CancellationError { throw CancellationError() }
            if let failure = error as? SwingAnalysisFailure { throw failure }
            throw SwingAnalysisFailure(message: error.localizedDescription, diagnostics: diagnostics)
        }
    }

    private struct SourceMetadata {
        var duration: Double
        var fps: Double
        var displaySize: CGSize
    }

    private static func sourceMetadata(for url: URL) async throws -> SourceMetadata {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(
                domain: "SwingKit", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "no video track"]
            )
        }
        let duration = try await asset.load(.duration).seconds
        let fps = Double(try await track.load(.nominalFrameRate))
        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let transformed = natural.applying(transform)
        return SourceMetadata(
            duration: duration,
            fps: fps,
            displaySize: CGSize(width: abs(transformed.width), height: abs(transformed.height))
        )
    }

    private static func measured<T>(
        _ signpostName: StaticString,
        key: String,
        jobID: UUID,
        diagnostics: inout AnalysisDiagnostics,
        operation: () async throws -> T
    ) async throws -> T {
        let signpostID = OSSignpostID(log: performanceLog)
        let id = jobID.uuidString
        return try await AnalysisStageTimer.measure(
            stage: key,
            diagnostics: &diagnostics,
            begin: {
                os_signpost(.begin, log: performanceLog, name: signpostName,
                            signpostID: signpostID, "job=%{public}s", id)
            },
            end: { succeeded in
                if succeeded {
                    os_signpost(.end, log: performanceLog, name: signpostName,
                                signpostID: signpostID,
                                "job=%{public}s result=success", id)
                } else {
                    os_signpost(.end, log: performanceLog, name: signpostName,
                                signpostID: signpostID,
                                "job=%{public}s result=failure", id)
                }
            },
            operation: operation
        )
    }

    private static func captureBoundary(
        _ diagnostics: inout AnalysisDiagnostics,
        callback: ((AnalysisDiagnostics) -> Void)?
    ) {
        diagnostics.recordThermalState()
        diagnostics.recordPeakMemory(AnalysisMemory.residentBytes())
        callback?(diagnostics)
    }

    /// Coarse address-to-finish window from the whole-clip fast pass: the first
    /// sustained stillness run's end (address, minus a margin) to the last sustained
    /// stillness run's start (finish, plus a margin) — same "genuine stillness, not
    /// a mid-swing pause" logic as CheckpointDetector's P1/P10 anchors, just looser
    /// (this only needs to bound the real extraction generously).
    static func normalizedWindow(_ requested: ClosedRange<Double>?,
                                 duration: Double) -> ClosedRange<Double> {
        let sourceEnd = max(0, duration)
        guard let requested else { return 0...sourceEnd }
        let start = min(sourceEnd, max(0, requested.lowerBound))
        let end = min(sourceEnd, max(start, requested.upperBound))
        return end - start >= 0.5 ? start...end : 0...sourceEnd
    }

    private static func findWindow(frames: [PoseFrame],
                                   bounds: ClosedRange<Double>) -> ClosedRange<Double> {
        let margin = 1.0
        let smoothed = Smoothing.smooth(frames)
        guard let motion = Motion.gripSpeed2D(smoothed) else { return bounds }
        let (times, _, speed) = motion
        guard !times.isEmpty else { return bounds }
        let stillRuns = Motion.quietRuns(times: times, speed: speed, threshold: 0.12, minDuration: 0.4)
        guard let first = stillRuns.first else { return bounds }
        let start = max(bounds.lowerBound, times[first.endIndex] - margin)
        let end: Double
        if let last = stillRuns.last, last.startIndex > first.endIndex + 4 {
            end = min(bounds.upperBound, times[last.startIndex] + margin)
        } else {
            end = bounds.upperBound
        }
        guard end > start + 0.5 else { return bounds }
        return start...end
    }
}
