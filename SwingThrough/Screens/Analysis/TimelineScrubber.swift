// The fine timeline under the headline checkpoints: all ten P-positions as ticks on a
// hairline, a draggable playhead, and a caption naming the position you're on. Drives
// the same model time as the video and avatar, so every pane stays in sync.
import SwiftUI
import SwingKit

struct TimelineScrubber: View {
    @Bindable var model: AnalysisModel

    private var trackStart: Double { model.report.frames.first?.time ?? 0 }
    private var trackEnd: Double { model.report.frames.last?.time ?? 1 }
    private var span: Double { max(trackEnd - trackStart, 0.001) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let frac = (model.time - trackStart) / span
            let x = CGFloat(min(max(frac, 0), 1)) * w

            ZStack(alignment: .topLeading) {
                // Caption above the playhead when the time sits on a checkpoint.
                if let p = nearestPosition() {
                    MicroLabel("\(p.shortName) · \(p.name)", color: .ink45, size: 8)
                        .fixedSize()
                        .position(x: captionX(x, width: w), y: 6)
                        .animation(.easeOut(duration: 0.18), value: p)
                }

                ZStack(alignment: .leading) {
                    Capsule().fill(Color.ink08).frame(height: 2)

                    // Checkpoint ticks
                    ForEach(model.report.checkpoints, id: \.position) { mark in
                        let tickX = CGFloat((mark.time - trackStart) / span) * w
                        let active = abs(model.time - mark.time) < 0.06
                        Circle()
                            .fill(active ? Color.fairwayDeep : Color.ink25)
                            .frame(width: active ? 5 : 3, height: active ? 5 : 3)
                            .position(x: tickX, y: 10)
                    }

                    // Playhead
                    Circle()
                        .fill(Color.ink)
                        .stroke(Color.paper, lineWidth: 1.5)
                        .frame(width: 11, height: 11)
                        .position(x: x, y: 10)
                }
                .frame(height: 20)
                .offset(y: 14)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let t = trackStart + Double(min(max(v.location.x / w, 0), 1)) * span
                        model.scrub(to: t)
                    }
            )
        }
        .frame(height: 36)
        .accessibilityIdentifier("timeline")
    }

    private func nearestPosition() -> SwingPosition? {
        model.report.checkpoints
            .min(by: { abs($0.time - model.time) < abs($1.time - model.time) })
            .flatMap { abs($0.time - model.time) < 0.08 ? $0.position : nil }
    }

    /// Keep the caption inside the card edges.
    private func captionX(_ x: CGFloat, width: CGFloat) -> CGFloat {
        min(max(x, 44), width - 44)
    }
}
