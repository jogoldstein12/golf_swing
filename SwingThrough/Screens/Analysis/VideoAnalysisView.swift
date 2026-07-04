// The video pane: the user's actual footage with the measured analysis drawn over it —
// tracked skeleton, base swing-plane line, plane-deviation callout, contact point, and
// tappable good/fault markers.
//
// Framing: the video renders at cover scale inside a card pane that can only show part
// of the portrait frame, so a precomputed, smoothed "camera window" follows the action —
// head + ball at address, the high hands at the top of the backswing. Video, skeleton,
// and markers live in ONE offset container so they can never desync while the window
// moves.
import AVFoundation
import SwiftUI
import SwingKit

// MARK: - Geometry

/// Cover-scale mapping from normalized video coordinates to a fixed display size.
/// The vertical window position comes from the model's smoothed framing track.
struct VideoPaneLayout {
    let pane: CGSize
    let videoSize: CGSize

    var scale: CGFloat {
        max(pane.width / max(videoSize.width, 1), pane.height / max(videoSize.height, 1))
    }
    var displaySize: CGSize {
        CGSize(width: videoSize.width * scale, height: videoSize.height * scale)
    }
    /// Normalized height of the visible window.
    var visibleFraction: Double {
        Double(pane.height / max(displaySize.height, 1))
    }
    /// Point in display (video) space — offset is applied by the container.
    func videoPoint(_ p: SIMD2<Double>) -> CGPoint {
        CGPoint(x: p.x * displaySize.width, y: p.y * displaySize.height)
    }
    /// Container offset for a normalized window top.
    func offsetY(forWindowTop top: Double) -> CGFloat {
        let raw = CGFloat(top) * displaySize.height
        return min(max(raw, 0), max(displaySize.height - pane.height, 0))
    }
}

// MARK: - Player layer

private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    final class LayerHost: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> LayerHost {
        let v = LayerHost()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resize   // geometry is controlled by the frame we give it
        return v
    }
    func updateUIView(_ v: LayerHost, context: Context) {}
}

// MARK: - The pane

struct VideoAnalysisView: View {
    @Bindable var model: AnalysisModel

    var body: some View {
        GeometryReader { geo in
            let layout = VideoPaneLayout(pane: geo.size, videoSize: model.videoSize)
            let windowTop = model.framingWindowTop(at: model.time, visible: layout.visibleFraction)
            let offsetY = layout.offsetY(forWindowTop: windowTop)

            ZStack(alignment: .topLeading) {
                // One container carries video + overlay + markers so the moving
                // window can never separate them.
                ZStack(alignment: .topLeading) {
                    PlayerLayerView(player: model.player)
                    OverlayCanvas(model: model, layout: layout)
                    markerButtons(layout)
                }
                .frame(width: layout.displaySize.width, height: layout.displaySize.height)
                .offset(y: -offsetY)
                .animation(model.isPlaying ? nil : .spring(response: 0.55, dampingFraction: 0.9),
                           value: offsetY)

                captions
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
        }
    }

    // MARK: markers

    @ViewBuilder
    private func markerButtons(_ layout: VideoPaneLayout) -> some View {
        let frame = model.report.frame(at: model.report.mark(model.selectedPosition)?.time ?? model.time)
        ForEach(model.markers(at: model.selectedPosition)) { marker in
            if let p = frame?.j2[marker.joint] {
                MarkerDot(marker: marker, selected: model.selectedMarker?.id == marker.id)
                    .position(layout.videoPoint(p))
                    .onTapGesture {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                            model.selectedMarker = marker
                        }
                    }
            }
        }
    }

    private var captions: some View {
        VStack {
            Spacer()
            HStack {
                MicroLabel("Your capture · \(model.report.view == .downTheLine ? "DTL" : "Face-on")",
                           color: .ink70, size: 8.5)
                    .scrimChip()
                Spacer()
                Text(timecode(model.time))
                    .font(Type.ui(9, .medium))
                    .foregroundStyle(Color.ink70)
                    .monospacedDigit()
                    .scrimChip()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }

    private func timecode(_ t: Double) -> String {
        let s = Int(t), f = Int((t - Double(s)) * Double(Int(model.report.frameRate)))
        return String(format: "00:%02d:%02d", s, f)
    }
}

/// A tappable good/fault marker pinned to a joint.
struct MarkerDot: View {
    let marker: SwingMarker
    let selected: Bool

    private var color: Color { marker.kind == .good ? .fairwayDeep : .brick }

    var body: some View {
        ZStack {
            if selected {
                Circle().fill(color.opacity(0.16)).frame(width: 34, height: 34)
            }
            Circle()
                .fill(Color.paper)
                .stroke(color, lineWidth: 2.2)
                .frame(width: 19, height: 19)
            Group {
                if marker.kind == .good {
                    CheckGlyph().stroke(color, style: .init(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .frame(width: 8, height: 7)
                } else {
                    CrossGlyph().stroke(color, style: .init(lineWidth: 2, lineCap: .round))
                        .frame(width: 6.5, height: 6.5)
                }
            }
        }
        .frame(width: 44, height: 44)     // generous hit target
        .contentShape(Circle())
        .animation(.spring(response: 0.32, dampingFraction: 0.75), value: selected)
    }
}

// MARK: - Overlay drawing

private struct OverlayCanvas: View {
    let model: AnalysisModel
    let layout: VideoPaneLayout

    var body: some View {
        Canvas { ctx, _ in
            guard let frame = model.currentFrame else { return }
            drawPlane(&ctx, frame: frame)
            drawSkeleton(&ctx, frame: frame)
        }
        .allowsHitTesting(false)
    }

    private func drawPlane(_ ctx: inout GraphicsContext, frame: PoseFrame) {
        guard let line = model.report.plane.basePlaneLine2D, line.count == 2 else { return }
        let a = layout.videoPoint(line[0])   // ground/ball end
        let b = layout.videoPoint(line[1])   // upper end

        // Extend the base plane line well past both ends.
        let dir = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let len = max(sqrt(dir.x * dir.x + dir.y * dir.y), 1)
        let u = CGPoint(x: dir.x / len, y: dir.y / len)
        let bFar = CGPoint(x: a.x + u.x * 1400, y: a.y + u.y * 1400)

        let active = model.selectedPosition == .p5 || model.selectedPosition == .p6
            || model.selectedPosition == .p7
        var plane = Path()
        plane.move(to: a)
        plane.addLine(to: bFar)
        ctx.stroke(plane, with: .color(.fairway.opacity(active ? 1 : 0.45)),
                   style: .init(lineWidth: 1.8, lineCap: .round, dash: [1, 6]))

        // Contact point at address/impact.
        if model.selectedPosition == .p1 || model.selectedPosition == .p7 {
            var ring = Path(ellipseIn: CGRect(x: a.x - 5.5, y: a.y - 5.5, width: 11, height: 11))
            ctx.stroke(ring, with: .color(.fairway), lineWidth: 2)
            ring = Path(ellipseIn: CGRect(x: a.x - 1.8, y: a.y - 1.8, width: 3.6, height: 3.6))
            ctx.fill(ring, with: .color(.fairway))
        }

        // Deviation callout when measurably off plane at the selected checkpoint.
        if let dev = model.report.plane.deviationByPosition[model.selectedPosition],
           abs(dev) > 1.5, let grip = frame.grip2 {
            let g = layout.videoPoint(grip)
            // Foot of perpendicular from grip to the plane line.
            let ag = CGPoint(x: g.x - a.x, y: g.y - a.y)
            let t = ag.x * u.x + ag.y * u.y
            let foot = CGPoint(x: a.x + u.x * t, y: a.y + u.y * t)
            var drop = Path()
            drop.move(to: g)
            drop.addLine(to: foot)
            let color: Color = dev > 0 ? .amber : .brick
            ctx.stroke(drop, with: .color(color), style: .init(lineWidth: 1.4, dash: [3, 3]))
            let label = Text(String(format: "%+.1f°", dev))
                .font(Type.ui(10, .bold))
                .foregroundStyle(color)
            ctx.draw(ctx.resolve(label), at: CGPoint(x: g.x + 14, y: g.y - 12), anchor: .leading)
        }
    }

    private func drawSkeleton(_ ctx: inout GraphicsContext, frame: PoseFrame) {
        var bones = Path()
        for (a, b) in Bones.all {
            guard let pa = frame.j2[a], let pb = frame.j2[b] else { continue }
            bones.move(to: layout.videoPoint(pa))
            bones.addLine(to: layout.videoPoint(pb))
        }
        ctx.stroke(bones, with: .color(.paper.opacity(0.85)),
                   style: .init(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

        // Head: circle sized from neck-head distance.
        if let head = frame.j2[.head], let neck = frame.j2[.neck] {
            let h = layout.videoPoint(head), n = layout.videoPoint(neck)
            let r = max(6, hypot(h.x - n.x, h.y - n.y) * 0.62)
            let circle = Path(ellipseIn: CGRect(x: h.x - r, y: h.y - r, width: 2 * r, height: 2 * r))
            ctx.stroke(circle, with: .color(.paper.opacity(0.85)), lineWidth: 2.2)
        }

        // Joints.
        for (_, p) in frame.j2 {
            let c = layout.videoPoint(p)
            let dot = Path(ellipseIn: CGRect(x: c.x - 1.8, y: c.y - 1.8, width: 3.6, height: 3.6))
            ctx.fill(dot, with: .color(.paper.opacity(0.9)))
        }

        // Grip.
        if let grip = frame.grip2 {
            let g = layout.videoPoint(grip)
            let dot = Path(ellipseIn: CGRect(x: g.x - 3.2, y: g.y - 3.2, width: 6.4, height: 6.4))
            ctx.fill(dot, with: .color(.fairway))
        }
    }
}
