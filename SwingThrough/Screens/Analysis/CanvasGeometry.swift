// NP-2 — the goal overlay drawn ON the actual video frame, not a schematic. The video
// pane renders at COVER scale (fill, not letterbox) with a moving vertical "camera
// window" (see VideoAnalysisView.swift's VideoPaneLayout) — so any overlay has to share
// that exact math or it will drift off the pixels the video shows. CanvasGeometry is the
// one place that math lives for non-video callers; it delegates to VideoPaneLayout
// rather than re-deriving scale/displaySize, so the two can never diverge.
import CoreGraphics
import SwiftUI
import SwingKit

// MARK: - Shared cover mapping

enum CanvasGeometry {
    /// Maps a normalized (0...1, top-left origin) video-space point into `rect`'s
    /// coordinate space under the SAME cover-fit VideoPaneLayout uses: the video is
    /// scaled to fully cover `rect` (never letterboxed) and centered on it, so a
    /// portrait clip in a shorter/wider rect overflows top and bottom rather than
    /// leaving bars. This is the static, centered map; a moving per-time vertical
    /// "camera window" offset (identical to the video's own) is applied by the caller,
    /// exactly as VideoAnalysisView applies it to the player itself.
    static func imagePoint(_ normalized: CGPoint, videoSize: CGSize, in rect: CGRect) -> CGPoint {
        let layout = VideoPaneLayout(pane: rect.size, videoSize: videoSize)
        let display = layout.displaySize
        let origin = CGPoint(x: rect.midX - display.width / 2, y: rect.midY - display.height / 2)
        let local = layout.videoPoint(SIMD2(Double(normalized.x), Double(normalized.y)))
        return CGPoint(x: origin.x + local.x, y: origin.y + local.y)
    }

    static func imagePoint(_ normalized: SIMD2<Double>, videoSize: CGSize, in rect: CGRect) -> CGPoint {
        imagePoint(CGPoint(x: normalized.x, y: normalized.y), videoSize: videoSize, in: rect)
    }
}

// MARK: - Metric resolution (mirrors SwingOverlay's own matching, public-surface only)

extension SwingReport {
    /// The coachable metric behind a goal, matched by label family — the same matching
    /// SwingOverlay.resolveMetric uses internally, reimplemented here against the public
    /// `coachableMetrics` surface so the view layer can read a goal's measurement
    /// quality (for the "Estimated" flag) without reaching into SwingKit internals.
    func coachableMetric(for goal: CoachGoal) -> MetricValue? {
        let target = goal.metricLabel.lowercased()
        if let hit = coachableMetrics.first(where: {
            target.contains($0.label.lowercased()) || $0.label.lowercased().contains(target)
        }) { return hit }
        if target.contains("plane") {
            return coachableMetrics.first { $0.label.lowercased().contains("plane") }
        }
        return nil
    }
}

// MARK: - The plane overlay, drawn in video pixel space

/// Draws goal #1's honest overlay plan directly over the video's own pixels. Honest by
/// construction: `planeLine2D` or `videoSize` being nil (the pipeline never measured a
/// shaft, or never recorded the source video's own dimensions) draws nothing at all —
/// never a guessed line. An estimated (non-`.measured`) plane read draws dashed/amber
/// and is captioned "Estimated" elsewhere; the raw pipeline word never appears here.
struct PlaneOverlay: View {
    /// The goal's resolved plan — nil (no scored goal yet) draws nothing.
    let plan: OverlayPlan?
    /// The measured base plane line in normalized image space: [ground/ball end, upper
    /// end]. Every ray is drawn from the ground/ball end — the one point the pipeline
    /// actually measured for every checkpoint.
    let planeLine2D: [SIMD2<Double>]?
    /// The source video's own pixel dimensions. nil is an honest gate: without them the
    /// normalized -> pixel aspect correction can't be trusted.
    let videoSize: CGSize?
    /// True when the plane goal's metric is not a confident `.measured` read.
    var isEstimated: Bool = false
    /// Mirrors CoachingCanvas's "more lines" disclosure so the two views always agree.
    var showAdvanced: Bool = false

    private var drawn: [OverlayPrimitive] {
        guard let plan else { return [] }
        return showAdvanced ? plan.primitives + plan.advancedOnly : plan.primitives
    }

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                guard let videoSize,
                      let line = planeLine2D, line.count == 2,
                      !drawn.isEmpty else { return }
                draw(&ctx, rect: CGRect(origin: .zero, size: size),
                     videoSize: videoSize, anchor: line[0])
            }
            .allowsHitTesting(false)
        }
        .clipped()
    }

    // MARK: drawing

    /// Normalized-space ray length (well past any edge of the unit frame once mapped),
    /// chosen in the SAME normalized/aspect-corrected space the pipeline's angles were
    /// measured in — synthesizing pixel-space cos/sin directly would silently distort
    /// the angle on a non-square video.
    private let reach: Double = 2.4

    private func draw(_ ctx: inout GraphicsContext, rect: CGRect, videoSize: CGSize, anchor: SIMD2<Double>) {
        let origin = CanvasGeometry.imagePoint(anchor, videoSize: videoSize, in: rect)

        func point(_ angleDeg: Double, _ length: Double) -> CGPoint {
            let r = angleDeg * .pi / 180
            let n = SIMD2(anchor.x + cos(r) * length, anchor.y - sin(r) * length)
            return CanvasGeometry.imagePoint(n, videoSize: videoSize, in: rect)
        }

        // Corridor first (it sits behind the lines).
        for case let .targetCorridor(low, high) in drawn {
            var wedge = Path()
            wedge.move(to: origin)
            wedge.addLine(to: point(low, reach))
            wedge.addLine(to: point(high, reach))
            wedge.closeSubpath()
            ctx.fill(wedge, with: .color(.fairway.opacity(0.20)))
        }

        // Ghost of the golfer's own prior clean swing.
        for case let .ghostClub(priorAngle) in drawn {
            var g = Path(); g.move(to: origin); g.addLine(to: point(priorAngle, reach))
            ctx.stroke(g, with: .color(.fairwayDeep.opacity(0.45)),
                       style: .init(lineWidth: 2, lineCap: .round, dash: [5, 5]))
        }

        // Held reference from address (advanced): straight up from the anchor.
        for case .heldReferenceLine in drawn {
            var h = Path(); h.move(to: origin); h.addLine(to: point(90, reach))
            ctx.stroke(h, with: .color(.bone.opacity(0.9)),
                       style: .init(lineWidth: 1.5, lineCap: .round, dash: [4, 5]))
        }

        // pathTrace is an honest advanced primitive but has no measured geometry to
        // draw yet — intentionally a no-op stub until path tracking lands.

        // The measured plane line, last so it reads on top. Brick when off-plane;
        // dashed amber when the read behind it is an estimate, not a measurement.
        for case let .actualPlaneLine(angle, state) in drawn {
            let off = state != .on && state != .neutral
            var line = Path(); line.move(to: origin); line.addLine(to: point(angle, reach))
            let color: Color = isEstimated ? .amber : (off ? .brick : .ink)
            let dash: [CGFloat] = isEstimated ? [6, 5] : []
            ctx.stroke(line, with: .color(color), style: .init(lineWidth: 2.5, lineCap: .round, dash: dash))
        }

        // "Move here" arrow from the current line toward the ghost.
        for case let .moveArrow(fromAngle, toAngle) in drawn {
            let a = point(fromAngle, reach * 0.42)
            let b = point(toAngle, reach * 0.42)
            var arm = Path(); arm.move(to: a); arm.addLine(to: b)
            ctx.stroke(arm, with: .color(.ink70), style: .init(lineWidth: 1.6, lineCap: .round))
            ctx.fill(arrowhead(at: b, from: a), with: .color(.ink70))
        }

        // The measured anchor itself.
        ctx.fill(Path(ellipseIn: CGRect(x: origin.x - 4, y: origin.y - 4, width: 8, height: 8)),
                 with: .color(.ink))
    }

    /// A small filled triangle pointing from `origin` toward `tip`.
    private func arrowhead(at tip: CGPoint, from origin: CGPoint) -> Path {
        let dx = tip.x - origin.x, dy = tip.y - origin.y
        let len = max(0.0001, (dx * dx + dy * dy).squareRoot())
        let ux = dx / len, uy = dy / len
        let size: CGFloat = 8
        let base = CGPoint(x: tip.x - ux * size, y: tip.y - uy * size)
        let px = -uy, py = ux
        var p = Path()
        p.move(to: tip)
        p.addLine(to: CGPoint(x: base.x + px * size * 0.5, y: base.y + py * size * 0.5))
        p.addLine(to: CGPoint(x: base.x - px * size * 0.5, y: base.y - py * size * 0.5))
        p.closeSubpath()
        return p
    }
}
