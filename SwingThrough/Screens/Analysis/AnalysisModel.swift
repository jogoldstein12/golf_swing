// View model for the analysis screen. One timeline drives everything: the video,
// the overlay skeleton, the 3D avatar, and the checkpoint scrubber all read `time`.
import AVFoundation
import Observation
import SwiftUI
import SwingKit

enum AnalysisPane: String, CaseIterable, Identifiable {
    case video, avatar, split
    var id: String { rawValue }
    var label: String {
        switch self {
        case .video: "Video"
        case .avatar: "3D"
        case .split: "Split"
        }
    }
}

@Observable
final class AnalysisModel {
    let report: SwingReport
    let videoURL: URL
    let videoSize: CGSize
    let player: AVPlayer

    var pane: AnalysisPane = .video
    var time: Double = 0
    var isPlaying = false
    var selectedMarker: SwingMarker?
    var selectedPosition: SwingPosition = .p1

    private var timeObserver: Any?

    /// Precomputed per-frame framing anchors (normalized video-y) for the moving
    /// camera window: the golfer's confident joints plus the ball/ground point.
    private struct FramingSample {
        let time: Double
        let top: Double
        let bottom: Double
        let gripY: Double?
    }
    private var framing: [FramingSample] = []

    init(report: SwingReport, videoURL: URL, videoSize: CGSize) {
        self.report = report
        self.videoURL = videoURL
        self.videoSize = videoSize
        self.player = AVPlayer(url: videoURL)
        player.actionAtItemEnd = .pause
        player.automaticallyWaitsToMinimizeStalling = false

        let ballY = report.plane.basePlaneLine2D?.first?.y
        framing = report.frames.compactMap { f in
            var lo = Double.infinity, hi = -Double.infinity
            for (j, p) in f.j2 where (f.confidence[j] ?? 1) > 0.35 {
                lo = Swift.min(lo, p.y)
                hi = Swift.max(hi, p.y)
            }
            guard lo < hi else { return nil }
            if let ballY { hi = Swift.max(hi, ballY) }
            return FramingSample(time: f.time, top: lo - 0.035, bottom: hi + 0.025,
                                 gripY: f.grip2?.y)
        }

        // Dev hook: ST_POS=p4 screenshots a specific checkpoint without UI driving.
        let devPos = ProcessInfo.processInfo.environment["ST_POS"]
            .flatMap { Int($0.dropFirst()) }.flatMap { SwingPosition(rawValue: $0) }
        let startPosition: SwingPosition = devPos ?? (report.mark(.p1) != nil ? .p1 : .p4)
        select(startPosition, animated: false)

        // Dev hook: ST_AUTOPLAY=1 starts playback after launch (screen-recording runs).
        if ProcessInfo.processInfo.environment["ST_AUTOPLAY"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.togglePlay()
            }
        }

        // The first seek races item readiness — re-seek once the item can render,
        // so the pane never sits on a blank layer at launch.
        if let item = player.currentItem {
            Task { @MainActor [weak self] in
                while item.status != .readyToPlay {
                    try? await Task.sleep(nanoseconds: 40_000_000)
                }
                guard let self, !self.isPlaying else { return }
                self.seek(to: self.time)
            }
        }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 60), queue: .main
        ) { [weak self] t in
            guard let self, self.isPlaying else { return }
            self.time = t.seconds
            self.syncSelectedPosition()
            if let end = self.report.frames.last?.time, t.seconds >= end - 0.02 {
                self.isPlaying = false
            }
        }
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
    }

    var currentFrame: PoseFrame? { report.frame(at: time) }

    /// Normalized top of the camera window at `time`, for a window that shows
    /// `visible` (0…1) of the video height. Center the action when it fits; when it
    /// can't, keep the grip's end of the action in view (high hands at the top of the
    /// swing, ball/ground through impact). Rule-applied tops are smoothed ±0.35s so
    /// the window glides rather than steps.
    func framingWindowTop(at time: Double, visible: Double) -> Double {
        guard !framing.isEmpty, visible > 0, visible < 1 else { return 0 }
        func ruleTop(_ s: FramingSample) -> Double {
            let span = s.bottom - s.top
            if span <= visible { return s.top - (visible - span) / 2 }
            if let g = s.gripY, g >= (s.top + s.bottom) / 2 { return s.bottom - visible }
            return s.top
        }
        let windowed = framing.filter { abs($0.time - time) <= 0.35 }
        guard !windowed.isEmpty else {
            var nearest = framing[0]
            for s in framing where abs(s.time - time) < abs(nearest.time - time) { nearest = s }
            return ruleTop(nearest)
        }
        return windowed.map(ruleTop).reduce(0, +) / Double(windowed.count)
    }

    var headline: [SwingPosition] {
        SwingPosition.headline.filter { report.mark($0) != nil }
    }

    func markers(at p: SwingPosition) -> [SwingMarker] {
        report.markers.filter { $0.position == p }
    }

    func select(_ p: SwingPosition, animated: Bool = true) {
        isPlaying = false
        player.pause()
        selectedPosition = p
        guard let mark = report.mark(p) else { return }
        time = mark.time
        seek(to: mark.time)
        let next = markers(at: p).first
        if animated {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { selectedMarker = next }
        } else {
            selectedMarker = next
        }
    }

    func togglePlay() {
        if isPlaying {
            isPlaying = false
            player.pause()
            return
        }
        // Restart from address if we're at the end.
        if let end = report.frames.last?.time, time >= end - 0.05 {
            let start = report.mark(.p1)?.time ?? report.frames.first?.time ?? 0
            time = start
            seek(to: start)
        }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { selectedMarker = nil }
        isPlaying = true
        player.play()
    }

    func scrub(to t: Double) {
        isPlaying = false
        player.pause()
        time = t
        seek(to: t)
        syncSelectedPosition()
    }

    private func seek(to t: Double) {
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Keep the scrubber highlight on the latest headline checkpoint we've passed.
    private func syncSelectedPosition() {
        let passed = headline
            .compactMap { p in report.mark(p).map { (p, $0.time) } }
            .filter { $0.1 <= time + 0.03 }
        if let latest = passed.max(by: { $0.1 < $1.1 }), latest.0 != selectedPosition {
            selectedPosition = latest.0
        }
    }
}
