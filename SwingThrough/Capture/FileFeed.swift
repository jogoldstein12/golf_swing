// Development feed: real-time playback loop of a bundled clip. An AVAssetReader decodes
// frames and a dedicated thread paces delivery to the wall clock, so the pose loop and
// the state machine run at true speed — identical timing behavior to the camera. At EOF
// the reader restarts and `sourceTime` wraps; the detector reads the wrap as a scene cut
// and resets to idle. "Recording" here retains nothing (the source *is* the bundled
// asset); `finishTake` cuts the requested segment out of it through the same exporter
// the camera uses, so the full accept path produces a real file URL either way.
import AVFoundation
import Foundation
import QuartzCore

final class FileFeed: CaptureFeed {
    var onFrame: ((FeedFrame) -> Void)?
    private(set) var info = FeedInfo()

    private let url: URL
    private let lock = NSLock()
    private var stopped = false
    private var takeActive = false
    private var duration: Double = 0
    private var thread: Thread?

    init(url: URL) { self.url = url }

    private var isStopped: Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped
    }

    func start() async -> FeedAvailability {
        let asset = AVURLAsset(url: url)
        do {
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                return .unavailable("fixture has no video track")
            }
            let natural = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let size = CGSize(width: abs(natural.applying(transform).width),
                              height: abs(natural.applying(transform).height))
            info = FeedInfo(fps: Double(try await track.load(.nominalFrameRate)),
                            size: size,
                            orientation: Self.orientation(for: transform))
            duration = try await asset.load(.duration).seconds
        } catch {
            return .unavailable("fixture unreadable: \(error.localizedDescription)")
        }
        let t = Thread { [weak self] in self?.pump() }
        t.name = "st.filefeed"
        t.qualityOfService = .userInitiated
        thread = t
        t.start()
        return .running
    }

    func stop() {
        lock.lock(); stopped = true; lock.unlock()
    }

    func beginTake() {
        lock.lock(); takeActive = true; lock.unlock()
    }

    func cancelTake() {
        lock.lock(); takeActive = false; lock.unlock()
    }

    func finishTake(fromSource: Double, toSource: Double) async throws -> URL {
        guard consumeTake() else { throw TakeError.noTake }
        // A capture that wrapped the loop boundary can't be represented as one segment
        // of the source; clamp to the tail that contains the swing.
        let from = toSource >= fromSource ? fromSource : 0
        return try await TakeExporter.trim(assetAt: url, from: from, to: toSource)
    }

    private func consumeTake() -> Bool {
        lock.lock(); defer { lock.unlock() }
        let active = takeActive
        takeActive = false
        return active
    }

    // MARK: - Pacing loop

    private func pump() {
        while !isStopped {
            autoreleasepool {
                guard let (reader, output) = makeReader() else {
                    lock.lock(); stopped = true; lock.unlock()
                    return
                }
                let base = CACurrentMediaTime()
                while !isStopped, let sb = output.copyNextSampleBuffer() {
                    guard CMSampleBufferGetImageBuffer(sb) != nil else { continue }
                    let pts = CMSampleBufferGetPresentationTimeStamp(sb).seconds
                    let target = base + pts
                    let now = CACurrentMediaTime()
                    if target > now { Thread.sleep(forTimeInterval: target - now) }
                    onFrame?(FeedFrame(sample: sb, time: target, sourceTime: pts))
                }
                reader.cancelReading()
            }
        }
    }

    private func makeReader() -> (AVAssetReader, AVAssetReaderTrackOutput)? {
        let asset = AVURLAsset(url: url)
        // Synchronous track access is fine here: the asset was fully loaded in start()
        // and this runs on the feed's own thread.
        guard let track = asset.tracks(withMediaType: .video).first,
              let reader = try? AVAssetReader(asset: asset) else { return nil }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            // IOSurface backing: AVSampleBufferDisplayLayer won't show plain
            // malloc-backed buffers on every runtime (the Simulator in particular).
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }
        return (reader, output)
    }

    static func orientation(for transform: CGAffineTransform) -> CGImagePropertyOrientation {
        let angle = atan2(Double(transform.b), Double(transform.a)) * 180 / .pi
        return switch Int(angle.rounded()) {
        case 90, -270: .right
        case 180, -180: .down
        case -90, 270: .left
        default: .up
        }
    }
}
