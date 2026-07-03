// Measurement layer, stage 1: video in → per-frame joint tracks out.
// 3D joints from VNDetectHumanBodyPose3DRequest (model space: meters, root at origin,
// +y up) drive all biomechanics; 2D joints from VNDetectHumanBodyPoseRequest (normalized
// image space, converted here to top-left origin) drive video overlays. Nothing is
// inferred by a model beyond joint positions — every metric downstream is geometry.
import AVFoundation
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
        public init(window: ClosedRange<Double>? = nil, sampleFPS: Double? = nil, include3D: Bool = true) {
            self.window = window; self.sampleFPS = sampleFPS; self.include3D = include3D
        }
    }

    public struct Result {
        public var frames: [PoseFrame]
        public var nativeFPS: Double
        public var duration: Double
        public var videoSize: CGSize      // display size (orientation applied)
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
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        if let w = options.window {
            reader.timeRange = CMTimeRange(
                start: CMTime(seconds: w.lowerBound, preferredTimescale: 600),
                end: CMTime(seconds: w.upperBound, preferredTimescale: 600))
        }
        guard reader.startReading() else {
            throw reader.error ?? NSError(domain: "SwingKit", code: 2)
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

        while let sample = output.copyNextSampleBuffer() {
            guard let pixels = CMSampleBufferGetImageBuffer(sample) else { continue }
            let t = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            if t - lastSampled < minStep { continue }
            lastSampled = t

            var frame = PoseFrame(time: t)
            let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: orientation)

            let req2D = VNDetectHumanBodyPoseRequest()
            var requests: [VNRequest] = [req2D]
            let req3D = VNDetectHumanBodyPose3DRequest()
            if options.include3D { requests.append(req3D) }
            try handler.perform(requests)

            if let obs = req2D.results?.max(by: { $0.confidence < $1.confidence }),
               let pts = try? obs.recognizedPoints(.all) {
                for (name, joint) in Self.map2D {
                    if let p = pts[name], p.confidence > 0.1 {
                        // Vision: origin bottom-left, y up → contract: top-left, y down.
                        frame.j2[joint] = SIMD2(Double(p.location.x), 1 - Double(p.location.y))
                        frame.confidence[joint] = Double(p.confidence)
                    }
                }
            }
            if options.include3D,
               let obs = req3D.results?.first,
               let pts = try? obs.recognizedPoints(.all) {
                for (name, joint) in Self.map3D {
                    if let p = pts[name] {
                        let c = p.position.columns.3
                        frame.j3[joint] = SIMD3(Double(c.x), Double(c.y), Double(c.z))
                    }
                }
                let m = obs.cameraOriginMatrix
                frame.cameraTransform = [
                    m.columns.0, m.columns.1, m.columns.2, m.columns.3,
                ].flatMap { [Double($0.x), Double($0.y), Double($0.z), Double($0.w)] }
                frame.bodyHeight = Double(obs.bodyHeight)
            }
            if !frame.j2.isEmpty || !frame.j3.isEmpty {
                frames.append(frame)
            }
            if let w = options.window {
                progress?(min(1, (t - w.lowerBound) / windowLength))
            } else {
                progress?(min(1, t / windowLength))
            }
        }
        if reader.status == .failed { throw reader.error ?? NSError(domain: "SwingKit", code: 3) }
        return Result(frames: frames, nativeFPS: fps, duration: duration, videoSize: displaySize)
    }
}
