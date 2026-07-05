// Measurement layer, stage 1: video in → per-frame joint tracks out.
// 3D joints from VNDetectHumanBodyPose3DRequest (model space: meters, root at origin,
// +y up) drive all biomechanics; 2D joints from VNDetectHumanBodyPoseRequest (normalized
// image space, converted here to top-left origin) drive video overlays. Nothing is
// inferred by a model beyond joint positions — every metric downstream is geometry.
import AVFoundation
import CoreImage
import Foundation
import Vision
import simd

public struct PoseExtractor {
    public struct Options {
        /// Analyze only this window of the source (seconds). nil = whole video.
        public var window: ClosedRange<Double>?
        /// Sample rate. nil = native frame rate.
        public var sampleFPS: Double?
        /// Skip 3D (fast pass for swing detection / overlays only).
        public var include3D: Bool
        /// Longest decoded pixel-buffer edge handed to Vision. nil keeps source size.
        public var maximumDimension: Int?
        /// Scale the pixel buffer by this factor before handing it to Vision (fast 2D
        /// pass over a whole clip: Vision pose detection is fine well below native
        /// 2.5K resolution, and shrinking the buffer cuts decode/convert cost, which
        /// dominates on this Mac without Neural Engine acceleration). nil = native
        /// resolution.
        public var downscale: Double?
        public init(window: ClosedRange<Double>? = nil, sampleFPS: Double? = nil,
                    include3D: Bool = true, maximumDimension: Int? = nil,
                    downscale: Double? = nil) {
            self.window = window; self.sampleFPS = sampleFPS; self.include3D = include3D
            self.maximumDimension = maximumDimension
            self.downscale = downscale
        }
    }

    public struct Result {
        public var frames: [PoseFrame]
        public var nativeFPS: Double
        public var duration: Double
        public var videoSize: CGSize      // display size (orientation applied)
        public var attemptedSamples: Int
        public var recoverableFrameErrors: Int
    }

    public init() {}

    private static let map3D: [VNHumanBodyPose3DObservation.JointName: Joint] = [
        .root: .pelvis, .spine: .spine, .centerShoulder: .neck, .centerHead: .head,
        .topHead: .topHead,
        .leftShoulder: .shoulderL, .rightShoulder: .shoulderR,
        .leftElbow: .elbowL, .rightElbow: .elbowR,
        .leftWrist: .wristL, .rightWrist: .wristR,
        .leftHip: .hipL, .rightHip: .hipR,
        .leftKnee: .kneeL, .rightKnee: .kneeR,
        .leftAnkle: .ankleL, .rightAnkle: .ankleR,
    ]

    private static let map2D: [VNHumanBodyPoseObservation.JointName: Joint] = [
        .nose: .head, .neck: .neck, .root: .pelvis,
        .leftShoulder: .shoulderL, .rightShoulder: .shoulderR,
        .leftElbow: .elbowL, .rightElbow: .elbowR,
        .leftWrist: .wristL, .rightWrist: .wristR,
        .leftHip: .hipL, .rightHip: .hipR,
        .leftKnee: .kneeL, .rightKnee: .kneeR,
        .leftAnkle: .ankleL, .rightAnkle: .ankleR,
    ]

    public func extract(from url: URL, options: Options = .init(),
                        progress: ((Double) -> Void)? = nil) async throws -> Result {
        try Task.checkCancellation()
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "SwingKit", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "no video track"])
        }
        let duration = try await asset.load(.duration).seconds
        let fps = Double(try await track.load(.nominalFrameRate))
        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let displaySize = CGSize(width: abs(natural.applying(transform).width),
                                 height: abs(natural.applying(transform).height))

        let reader = try AVAssetReader(asset: asset)
        var outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        ]
        if let maximum = options.maximumDimension, maximum > 0 {
            let sourceMaximum = max(natural.width, natural.height)
            let scale = min(1, CGFloat(maximum) / max(1, sourceMaximum))
            outputSettings[kCVPixelBufferWidthKey as String] = max(2, Int(natural.width * scale))
            outputSettings[kCVPixelBufferHeightKey as String] = max(2, Int(natural.height * scale))
        }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw NSError(domain: "SwingKit", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "video frames could not be decoded"])
        }
        reader.add(output)
        if let w = options.window {
            reader.timeRange = CMTimeRange(
                start: CMTime(seconds: w.lowerBound, preferredTimescale: 600),
                end: CMTime(seconds: w.upperBound, preferredTimescale: 600))
        }
        guard reader.startReading() else {
            throw reader.error ?? NSError(domain: "SwingKit", code: 2)
        }
        defer {
            if reader.status == .reading {
                reader.cancelReading()
            }
        }

        // Video frames arrive rotated per preferredTransform; Vision needs the
        // orientation to interpret the pixel buffer correctly.
        let angle = atan2(Double(transform.b), Double(transform.a)) * 180 / .pi
        let orientation: CGImagePropertyOrientation = switch Int(angle.rounded()) {
        case 90, -270: .right
        case 180, -180: .down
        case -90, 270: .left
        default: .up
        }

        var frames: [PoseFrame] = []
        var lastSampled = -Double.infinity
        let minStep = options.sampleFPS.map { 1.0 / $0 - 1e-6 } ?? 0
        let windowLength = (options.window.map { $0.upperBound - $0.lowerBound }) ?? duration
        let ciContext = options.downscale != nil ? CIContext(options: [.useSoftwareRenderer: false]) : nil
        var progressThrottler = AnalysisProgressThrottler(maximumUpdatesPerSecond: 10)
        let request2D = VNDetectHumanBodyPoseRequest()
        let request3D = options.include3D ? VNDetectHumanBodyPose3DRequest() : nil
        var attemptedSamples = 0
        var frameErrors = 0
        var consecutiveFrameErrors = 0

        while reader.status == .reading {
            try Task.checkCancellation()
            guard let sample = output.copyNextSampleBuffer() else { break }
            guard var pixels = CMSampleBufferGetImageBuffer(sample) else { continue }
            let t = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            if t - lastSampled < minStep { continue }
            lastSampled = t
            attemptedSamples += 1

            if let factor = options.downscale, let ctx = ciContext,
               let scaled = Self.downscaled(pixels, factor: factor, context: ctx) {
                pixels = scaled
            }

            try Task.checkCancellation()
            let frame: PoseFrame
            do {
                frame = try autoreleasepool {
                    try Self.analyzeFrame(
                        pixels: pixels,
                        time: t,
                        orientation: orientation,
                        request2D: request2D,
                        request3D: request3D
                    )
                }
                consecutiveFrameErrors = 0
            } catch {
                frameErrors += 1
                consecutiveFrameErrors += 1
                let budget = PoseFailureBudget(
                    attempted: attemptedSamples,
                    failed: frameErrors,
                    consecutiveFailures: consecutiveFrameErrors
                )
                if budget.shouldAbort {
                    throw PoseExtractionError.frameFailureBudgetExceeded(
                        failed: frameErrors,
                        attempted: attemptedSamples
                    )
                }
                continue
            }
            try Task.checkCancellation()
            if !frame.j2.isEmpty || !frame.j3.isEmpty {
                try Task.checkCancellation()
                frames.append(frame)
            }
            if progress != nil {
                let fraction: Double
                if let w = options.window {
                    fraction = min(1, (t - w.lowerBound) / windowLength)
                } else {
                    fraction = min(1, t / windowLength)
                }
                if progressThrottler.shouldEmit(
                    progress: fraction,
                    now: ProcessInfo.processInfo.systemUptime
                ) {
                    progress?(fraction)
                }
            }
        }
        if progressThrottler.shouldEmit(progress: 1, now: ProcessInfo.processInfo.systemUptime) {
            progress?(1)
        }
        if reader.status == .failed { throw reader.error ?? NSError(domain: "SwingKit", code: 3) }
        if frames.isEmpty, frameErrors > 0 {
            throw PoseExtractionError.frameFailureBudgetExceeded(
                failed: frameErrors, attempted: attemptedSamples
            )
        }
        return Result(
            frames: frames,
            nativeFPS: fps,
            duration: duration,
            videoSize: displaySize,
            attemptedSamples: attemptedSamples,
            recoverableFrameErrors: frameErrors
        )
    }

    private static func analyzeFrame(
        pixels: CVPixelBuffer,
        time: Double,
        orientation: CGImagePropertyOrientation,
        request2D: VNDetectHumanBodyPoseRequest,
        request3D: VNDetectHumanBodyPose3DRequest?
    ) throws -> PoseFrame {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: orientation)
        var requests: [VNRequest] = [request2D]
        if let request3D { requests.append(request3D) }
        try handler.perform(requests)

        var frame = PoseFrame(time: time)
        if let observation = request2D.results?.max(by: { $0.confidence < $1.confidence }),
           let points = try? observation.recognizedPoints(.all) {
            for (name, joint) in map2D {
                if let point = points[name], point.confidence > 0.1 {
                    frame.j2[joint] = SIMD2(
                        Double(point.location.x), 1 - Double(point.location.y)
                    )
                    frame.confidence[joint] = Double(point.confidence)
                }
            }
        }
        if let request3D,
           let observation = request3D.results?.first,
           let points = try? observation.recognizedPoints(.all) {
            for (name, joint) in map3D {
                if let point = points[name] {
                    let column = point.position.columns.3
                    frame.j3[joint] = SIMD3(
                        Double(column.x), Double(column.y), Double(column.z)
                    )
                }
            }
            let matrix = observation.cameraOriginMatrix
            frame.cameraTransform = [
                matrix.columns.0, matrix.columns.1, matrix.columns.2, matrix.columns.3,
            ].flatMap { [Double($0.x), Double($0.y), Double($0.z), Double($0.w)] }
            frame.bodyHeight = Double(observation.bodyHeight)
        }
        return frame
    }

    /// Renders `pixelBuffer` scaled by `factor` into a freshly-allocated 32BGRA
    /// pixel buffer via Core Image (cheap relative to the Vision request itself).
    private static func downscaled(_ pixelBuffer: CVPixelBuffer, factor: Double, context: CIContext) -> CVPixelBuffer? {
        let w = CVPixelBufferGetWidth(pixelBuffer), h = CVPixelBufferGetHeight(pixelBuffer)
        let newW = max(2, Int(Double(w) * factor)), newH = max(2, Int(Double(h) * factor))
        var out: CVPixelBuffer?
        let attrs: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
        CVPixelBufferCreate(kCFAllocatorDefault, newW, newH, kCVPixelFormatType_32BGRA,
                            attrs as CFDictionary, &out)
        guard let out else { return nil }
        let ci = CIImage(cvPixelBuffer: pixelBuffer).transformed(by: CGAffineTransform(scaleX: factor, y: factor))
        context.render(ci, to: out)
        return out
    }
}

public enum PoseExtractionError: LocalizedError, Equatable, Sendable {
    case frameFailureBudgetExceeded(failed: Int, attempted: Int)

    public var errorDescription: String? {
        switch self {
        case .frameFailureBudgetExceeded:
            "Too many video frames could not be analyzed. Try a shorter, well-lit clip."
        }
    }
}

public enum PoseSamplingBudget {
    public static func maximumSampleCount(duration: Double, sampleFPS: Double) -> Int {
        guard duration > 0, sampleFPS > 0 else { return 0 }
        return Int(ceil(duration * sampleFPS)) + 1
    }
}

public struct PoseFailureBudget: Sendable, Equatable {
    public var attempted: Int
    public var failed: Int
    public var consecutiveFailures: Int

    public init(attempted: Int, failed: Int, consecutiveFailures: Int) {
        self.attempted = attempted
        self.failed = failed
        self.consecutiveFailures = consecutiveFailures
    }

    public var shouldAbort: Bool {
        consecutiveFailures > 5
            || (attempted >= 20 && Double(failed) / Double(max(1, attempted)) > 0.10)
    }
}
