// The feed abstraction that makes capture verifiable: the pose loop, the swing-detection
// state machine, and the recording path all consume timestamped frames through one
// protocol, whether they come from the back camera (device) or a bundled clip paced to
// the wall clock (Simulator, ST_FEED=file). Downstream code cannot tell the difference —
// that is the point.
import AVFoundation
import CoreVideo
import Foundation

/// One frame from a feed.
/// `time` is a monotonic presentation clock (seconds) that drives all detector timers;
/// `sourceTime` is the media time inside the recordable source (camera take file /
/// bundled asset) used to trim the final clip. For a looping file feed, `sourceTime`
/// wraps at the clip boundary — the detector treats that as a scene cut.
struct FeedFrame {
    let sample: CMSampleBuffer
    let time: Double
    let sourceTime: Double
    var pixelBuffer: CVPixelBuffer? { CMSampleBufferGetImageBuffer(sample) }
}

struct FeedInfo {
    var fps: Double = 0
    var size: CGSize = .zero                      // display size, orientation applied
    /// Orientation the pose service must hand Vision. Both feeds normally deliver
    /// upright buffers (.up); the camera falls back to .right if its connection cannot
    /// rotate in hardware.
    var orientation: CGImagePropertyOrientation = .up
    var aspect: CGFloat { size.height > 0 ? size.width / size.height : 9.0 / 16.0 }
}

enum FeedAvailability: Equatable {
    case running
    /// Camera permission denied or restricted → designed empty state, never an alert.
    case denied
    /// No usable feed (Simulator has no camera; fixture missing). Message is dev-facing.
    case unavailable(String)
}

protocol CaptureFeed: AnyObject {
    /// Called on the feed's delivery queue (never main) for every frame.
    var onFrame: ((FeedFrame) -> Void)? { get set }
    var info: FeedInfo { get }
    func start() async -> FeedAvailability
    func stop()
    /// Begin retaining media so a later trim can reach back before the trigger.
    /// Called at address-stillness onset — the ring-buffer role: everything from here
    /// until `finishTake` is recoverable, and the trim decides what survives.
    func beginTake()
    /// Discard the retained media (stillness broke, subject left, loop wrapped).
    func cancelTake()
    /// Produce the final trimmed clip covering `fromSource...toSource` (media time,
    /// clamped to what the take actually holds).
    func finishTake(fromSource: Double, toSource: Double) async throws -> URL
}

enum TakeError: Error, LocalizedError {
    case noTake, emptyRange, exportFailed(String)
    var errorDescription: String? {
        switch self {
        case .noTake: "No take in progress"
        case .emptyRange: "Trimmed range was empty"
        case .exportFailed(let why): "Export failed: \(why)"
        }
    }
}

/// Shared trim/export. Both feeds end a take by cutting a precise segment out of a
/// source asset. Re-encode (HighestQuality preset), not passthrough: passthrough can
/// only cut on sync frames, and a capture that starts seconds before the address —
/// or mid-GOP garbage — is worse than one extra encode of a five-second clip. The
/// output is the analysis artifact; cut precision wins.
enum TakeExporter {
    static func swingsDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("Swings", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func trim(assetAt url: URL, from: Double, to: Double) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let a = max(0, from)
        let b = min(duration, max(a, to))
        guard b - a > 0.4 else { throw TakeError.emptyRange }
        guard let session = AVAssetExportSession(
            asset: asset, presetName: AVAssetExportPresetHighestQuality)
        else { throw TakeError.exportFailed("no export session") }
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: a, preferredTimescale: 600),
            end: CMTime(seconds: b, preferredTimescale: 600))
        let stamp = ISO8601DateFormatter().string(from: .now)
            .replacingOccurrences(of: ":", with: "-")
        let out = try swingsDirectory().appendingPathComponent("swing-\(stamp).mov")
        try? FileManager.default.removeItem(at: out)
        do {
            try await session.export(to: out, as: .mov)
        } catch {
            throw TakeError.exportFailed(error.localizedDescription)
        }
        return out
    }
}
