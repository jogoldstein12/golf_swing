// Preview plumbing. One AVSampleBufferDisplayLayer shows whatever the feed delivers —
// camera or file — so the on-screen image is provably the same stream the pose loop
// and recorder consume. The review loop is a bare AVPlayerLayer + AVPlayerLooper;
// no AVKit chrome.
import AVFoundation
import SwiftUI
import UIKit

/// Thread-safe frame sink for the live preview. Feeds enqueue from their delivery
/// queues; the layer attaches from the main thread.
final class PreviewSink {
    private let lock = NSLock()
    private weak var layer: AVSampleBufferDisplayLayer?

    func attach(_ layer: AVSampleBufferDisplayLayer) {
        lock.lock(); self.layer = layer; lock.unlock()
    }

    func enqueue(_ sample: CMSampleBuffer) {
        lock.lock()
        let layer = layer
        lock.unlock()
        guard let layer else { return }
        // Live preview: show each frame as it arrives, ignore PTS (a looping file
        // feed's timestamps restart; the camera's are already realtime).
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sample, createIfNecessary: true), CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0),
                                     to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dict,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        let renderer = layer.sampleBufferRenderer
        if renderer.status == .failed { renderer.flush() }
        renderer.enqueue(sample)
        if renderer.status == .failed, !loggedFailure {
            loggedFailure = true
            NSLog("PreviewSink: renderer failed (%@)",
                  renderer.error?.localizedDescription ?? "unknown")
        }
    }
    private var loggedFailure = false
}

struct FeedPreviewView: UIViewRepresentable {
    let sink: PreviewSink

    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }
        var displayLayer: AVSampleBufferDisplayLayer? { layer as? AVSampleBufferDisplayLayer }
    }

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.displayLayer?.videoGravity = .resizeAspectFill
        view.backgroundColor = .clear
        if let layer = view.displayLayer { sink.attach(layer) }
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) {}
}

/// Muted, seamless loop of the trimmed take for the review card.
struct LoopingPlayerView: UIViewRepresentable {
    let url: URL
    let playbackRange: ClosedRange<Double>?

    init(url: URL, playbackRange: ClosedRange<Double>? = nil) {
        self.url = url
        self.playbackRange = playbackRange
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer? { layer as? AVPlayerLayer }
        var looper: AVPlayerLooper?
        var playbackRange: ClosedRange<Double>?
    }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        configure(view)
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        guard view.playbackRange != playbackRange else { return }
        configure(view)
    }

    private func configure(_ view: PlayerView) {
        view.playerLayer?.player?.pause()
        view.looper = nil
        let player = AVQueuePlayer()
        player.isMuted = true
        let item = AVPlayerItem(url: url)
        if let playbackRange {
            view.looper = AVPlayerLooper(
                player: player,
                templateItem: item,
                timeRange: CMTimeRange(
                    start: CMTime(seconds: playbackRange.lowerBound, preferredTimescale: 600),
                    end: CMTime(seconds: playbackRange.upperBound, preferredTimescale: 600)
                )
            )
        } else {
            view.looper = AVPlayerLooper(player: player, templateItem: item)
        }
        view.playerLayer?.player = player
        view.playerLayer?.videoGravity = .resizeAspectFill
        view.playbackRange = playbackRange
        player.play()
    }

    static func dismantleUIView(_ view: PlayerView, coordinator: ()) {
        view.playerLayer?.player?.pause()
        view.looper = nil
        view.playerLayer?.player = nil
    }
}
