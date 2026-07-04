// Live pose loop: Vision's 2D body-pose request over feed frames, throttled to ~15–18Hz
// with latest-frame-wins semantics on a background queue. Emits joints in the PoseFrame
// contract's 2D convention (normalized, top-left origin, y down), a confident-joint
// bounding box, and the mean luma of the frame (the "enough light" signal) — everything
// the setup checklist and the swing detector need, nothing more.
import CoreVideo
import Foundation
import SwingKit
import Vision

struct LivePoseSample {
    var time: Double
    var sourceTime: Double
    var joints: [SwingKit.Joint: SIMD2<Double>] = [:]
    var confidence: [SwingKit.Joint: Double] = [:]
    /// Normalized bbox over joints with confidence ≥ 0.3; nil when no subject.
    var bbox: CGRect?
    var meanLuma: Double = 0

    func point(_ j: SwingKit.Joint, min c: Double = 0.25) -> SIMD2<Double>? {
        guard let p = joints[j], (confidence[j] ?? 0) >= c else { return nil }
        return p
    }
    /// Grip proxy: wrist midpoint, falling back to whichever wrist Vision can see
    /// (down-the-line hides the far arm at address).
    var grip: SIMD2<Double>? {
        let l = point(.wristL, min: 0.15), r = point(.wristR, min: 0.15)
        if let l, let r { return (l + r) * 0.5 }
        return l ?? r
    }
}

final class LivePoseService {
    /// Delivered on the main queue.
    var onSample: ((LivePoseSample) -> Void)?
    var orientation: CGImagePropertyOrientation = .up
    /// Dev-harness fallback: some Simulator runtimes ship without the body-pose model
    /// weights (`cnn_human_pose.espresso.weights`), so the Vision request cannot even
    /// set up. When the file feed drives, the controller installs the fixture's
    /// Vision-precomputed tracks and joints are looked up by source time instead.
    /// The live path is unchanged and always preferred when the request executes.
    var fixtureTracks: [PoseFrame] = []
    private var visionBroken = false

    private let queue = DispatchQueue(label: "st.pose", qos: .userInitiated)
    private let lock = NSLock()
    private var pending: FeedFrame?
    private var busy = false
    private var lastAccepted = -Double.infinity
    /// ≥55ms between Vision passes → ≤18Hz, and slower gracefully if Vision is slower.
    private let minInterval = 0.055

    private static let map2D: [VNHumanBodyPoseObservation.JointName: SwingKit.Joint] = [
        .nose: .head, .neck: .neck, .root: .pelvis,
        .leftShoulder: .shoulderL, .rightShoulder: .shoulderR,
        .leftElbow: .elbowL, .rightElbow: .elbowR,
        .leftWrist: .wristL, .rightWrist: .wristR,
        .leftHip: .hipL, .rightHip: .hipR,
        .leftKnee: .kneeL, .rightKnee: .kneeR,
        .leftAnkle: .ankleL, .rightAnkle: .ankleR,
    ]

    /// Feed-thread entry. Never blocks: the newest frame replaces any waiting one.
    func submit(_ frame: FeedFrame) {
        lock.lock()
        pending = frame
        let shouldStart = !busy
        if shouldStart { busy = true }
        lock.unlock()
        if shouldStart { queue.async { [weak self] in self?.drain() } }
    }

    private func drain() {
        while true {
            lock.lock()
            guard let frame = pending, frame.time - lastAccepted >= minInterval else {
                busy = false
                lock.unlock()
                return
            }
            pending = nil
            lastAccepted = frame.time
            lock.unlock()
            process(frame)
        }
    }

    private func process(_ frame: FeedFrame) {
        guard let pixels = frame.pixelBuffer else { return }
        var sample = LivePoseSample(time: frame.time, sourceTime: frame.sourceTime)
        sample.meanLuma = Self.meanLuma(of: pixels)

        if !visionBroken {
            let request = VNDetectHumanBodyPoseRequest()
            let handler = VNImageRequestHandler(cvPixelBuffer: pixels,
                                                orientation: orientation)
            do {
                try handler.perform([request])
                if let obs = request.results?.max(by: { $0.confidence < $1.confidence }),
                   let points = try? obs.recognizedPoints(.all) {
                    for (name, joint) in Self.map2D {
                        if let p = points[name], p.confidence > 0.1 {
                            // Vision: origin bottom-left, y up → contract: top-left, y down.
                            sample.joints[joint] = SIMD2(Double(p.location.x),
                                                         1 - Double(p.location.y))
                            sample.confidence[joint] = Double(p.confidence)
                        }
                    }
                }
            } catch {
                visionBroken = true
                NSLog("LivePoseService: Vision unavailable (%@)%@",
                      error.localizedDescription,
                      fixtureTracks.isEmpty ? "" : " — using fixture tracks")
            }
        }
        if visionBroken, !fixtureTracks.isEmpty,
           let track = nearestTrack(to: frame.sourceTime) {
            sample.joints = track.j2
            sample.confidence = track.confidence
        }

        let confident = sample.joints.filter { (sample.confidence[$0.key] ?? 0) >= 0.3 }
        if confident.count >= 4 {
            let xs = confident.values.map(\.x), ys = confident.values.map(\.y)
            if let x0 = xs.min(), let x1 = xs.max(),
               let y0 = ys.min(), let y1 = ys.max() {
                sample.bbox = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
            }
        }
        DispatchQueue.main.async { [onSample] in onSample?(sample) }
    }

    /// Binary search on the time-sorted fixture tracks; nil beyond 100ms.
    private func nearestTrack(to t: Double) -> PoseFrame? {
        guard !fixtureTracks.isEmpty else { return nil }
        var lo = 0, hi = fixtureTracks.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if fixtureTracks[mid].time < t { lo = mid + 1 } else { hi = mid }
        }
        if lo > 0, abs(fixtureTracks[lo - 1].time - t) < abs(fixtureTracks[lo].time - t) {
            lo -= 1
        }
        return abs(fixtureTracks[lo].time - t) <= 0.1 ? fixtureTracks[lo] : nil
    }

    /// Mean luma 0…1, subsampled. Reads the luma plane of 420 formats directly and
    /// approximates from green for anything else.
    static func meanLuma(of buffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let format = CVPixelBufferGetPixelFormatType(buffer)
        let planar = format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange

        let width: Int, height: Int, stride: Int, offset: Int, step: Int
        guard let base: UnsafeMutableRawPointer = planar
            ? CVPixelBufferGetBaseAddressOfPlane(buffer, 0)
            : CVPixelBufferGetBaseAddress(buffer)
        else { return 0 }
        if planar {
            width = CVPixelBufferGetWidthOfPlane(buffer, 0)
            height = CVPixelBufferGetHeightOfPlane(buffer, 0)
            stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
            offset = 0; step = 1
        } else {
            width = CVPixelBufferGetWidth(buffer)
            height = CVPixelBufferGetHeight(buffer)
            stride = CVPixelBufferGetBytesPerRow(buffer)
            offset = 1; step = 4                     // G channel of BGRA
        }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var total = 0, count = 0
        var y = 0
        while y < height {
            let row = y * stride
            var x = 0
            while x < width {
                total += Int(bytes[row + x * step + offset])
                count += 1
                x += 16
            }
            y += 16
        }
        return count > 0 ? Double(total) / Double(count) / 255.0 : 0
    }
}
