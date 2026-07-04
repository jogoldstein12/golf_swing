// Device feed: back camera through AVCaptureSession, portrait, 60fps-class format.
// Frames flow out through the same `onFrame` path as FileFeed; recording is an
// AVAssetWriter that starts retaining frames at address-stillness onset (the pre-roll
// guarantee) and is trimmed to the swing by the shared exporter afterwards.
//
// This class compiles into every build but is inert in the Simulator (no camera device
// → `.unavailable`); the configuration is deliberately standard AVFoundation so it
// plausibly works on hardware without exotic-API risk. Real-device verification is a
// later pass.
import AVFoundation
import Foundation
import QuartzCore

final class CameraFeed: NSObject, CaptureFeed, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onFrame: ((FeedFrame) -> Void)?
    private(set) var info = FeedInfo()

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "st.camera.session")
    /// All frame delivery *and* writer mutation happens on this one queue, so the
    /// writer lifecycle needs no locks.
    private let frameQueue = DispatchQueue(label: "st.camera.frames", qos: .userInitiated)

    // Writer state — touched only on frameQueue.
    private var takeRequested = false
    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var takeURL: URL?
    private var firstPTS: Double?

    func start() async -> FeedAvailability {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { return .denied }
        default:
            break
        }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video, position: .back) else {
            return .unavailable("no back camera on this device")
        }
        return await withCheckedContinuation { cont in
            sessionQueue.async { [self] in
                cont.resume(returning: configure(device))
            }
        }
    }

    private func configure(_ device: AVCaptureDevice) -> FeedAvailability {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .inputPriority   // the chosen format governs

        guard let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            return .unavailable("camera input rejected")
        }
        session.addInput(input)

        // Format selection: consider formats whose smaller axis is 1080p-class
        // (900–1200 px; 4K costs Vision latency and file size without helping 2D pose).
        // Among those, take the highest supported max frame rate that is ≥ 60; ties
        // break toward the smaller sensor area. If nothing reaches 60 fps, fall back to
        // the fastest 1080p-class format there is and report its true rate in the take
        // metadata — never pretend.
        var best: (format: AVCaptureDevice.Format, fps: Double)?
        for format in device.formats {
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let minSide = min(dims.width, dims.height)
            let maxSide = max(dims.width, dims.height)
            guard (900...1200).contains(minSide), maxSide <= 2200 else { continue }
            let maxRate = format.videoSupportedFrameRateRanges
                .map(\.maxFrameRate).max() ?? 0
            guard maxRate > (best?.fps ?? 0) else { continue }
            best = (format, maxRate)
        }
        var fps = 30.0
        if let best {
            let target = best.fps >= 60 ? min(best.fps, 120) : best.fps
            do {
                try device.lockForConfiguration()
                device.activeFormat = best.format
                // Lock a steady cadence: tempo math downstream wants uniform frame
                // spacing, not an adaptive rate.
                let duration = CMTime(value: 1, timescale: CMTimeScale(target))
                device.activeVideoMinFrameDuration = duration
                device.activeVideoMaxFrameDuration = duration
                device.unlockForConfiguration()
                fps = target
            } catch {
                fps = 30
            }
        }

        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: frameQueue)
        guard session.canAddOutput(output) else {
            return .unavailable("camera output rejected")
        }
        session.addOutput(output)

        var orientation = CGImagePropertyOrientation.up
        if let conn = output.connection(with: .video) {
            if conn.isVideoRotationAngleSupported(90) {
                conn.videoRotationAngle = 90    // buffers arrive portrait
            } else {
                orientation = .right            // deliver sideways, tell Vision
            }
        }

        let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let portrait = CGSize(width: CGFloat(min(dims.width, dims.height)),
                              height: CGFloat(max(dims.width, dims.height)))
        info = FeedInfo(fps: fps, size: portrait, orientation: orientation)

        session.startRunning()
        return .running
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
        frameQueue.async { [self] in teardownWriter(delete: true) }
    }

    // MARK: - Frame delivery

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        appendIfRecording(sampleBuffer, pts: pts)
        onFrame?(FeedFrame(sample: sampleBuffer, time: CACurrentMediaTime(), sourceTime: pts))
    }

    // MARK: - Take lifecycle (ring-buffer role)

    func beginTake() {
        frameQueue.async { [self] in
            guard writer == nil else { return }
            takeRequested = true
        }
    }

    func cancelTake() {
        frameQueue.async { [self] in
            takeRequested = false
            teardownWriter(delete: true)
        }
    }

    private func appendIfRecording(_ sb: CMSampleBuffer, pts: Double) {
        if writer == nil && takeRequested { startWriter() }
        guard let writer, let input = writerInput else { return }
        if writer.status == .unknown {
            writer.startWriting()
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sb))
            firstPTS = pts
        }
        guard writer.status == .writing, input.isReadyForMoreMediaData else { return }
        input.append(sb)
    }

    private func startWriter() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("take-\(UUID().uuidString).mov")
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return }
        let settings = output.recommendedVideoSettingsForAssetWriter(writingTo: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { return }
        writer.add(input)
        self.writer = writer
        self.writerInput = input
        self.takeURL = url
        self.firstPTS = nil
        self.takeRequested = false
    }

    private func teardownWriter(delete: Bool) {
        if let writer, writer.status == .writing { writer.cancelWriting() }
        if delete, let takeURL { try? FileManager.default.removeItem(at: takeURL) }
        writer = nil; writerInput = nil; takeURL = nil; firstPTS = nil
    }

    func finishTake(fromSource: Double, toSource: Double) async throws -> URL {
        let (writer, url, first): (AVAssetWriter?, URL?, Double?) =
            await withCheckedContinuation { cont in
                frameQueue.async { [self] in
                    let triple = (self.writer, self.takeURL, self.firstPTS)
                    self.writer = nil; self.writerInput = nil; self.takeURL = nil
                    cont.resume(returning: triple)
                }
            }
        guard let writer, let url, let first, writer.status == .writing else {
            throw TakeError.noTake
        }
        writerInputFinish(writer)
        await writer.finishWriting()
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: url)
            throw TakeError.exportFailed(writer.error?.localizedDescription ?? "writer failed")
        }
        defer { try? FileManager.default.removeItem(at: url) }
        // Take-file time = source PTS rebased to the first written frame.
        return try await TakeExporter.trim(assetAt: url,
                                           from: fromSource - first,
                                           to: toSource - first)
    }

    private func writerInputFinish(_ writer: AVAssetWriter) {
        writer.inputs.forEach { $0.markAsFinished() }
    }
}
