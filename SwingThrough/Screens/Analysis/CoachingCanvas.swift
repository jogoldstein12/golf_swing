// WS-E — the coaching canvas. Draws goal #1's OverlayPlan schematically over a small
// pane anchored to the ball, plus the external-focus caption and the two next actions
// ("see the fix" seeks the scrubber to the fault checkpoint; "drill" opens its page).
// Honest by construction: it only draws the primitives SwingOverlay handed it — a
// withheld metric yields no line, so there is nothing here to fabricate. Novice sees the
// one cue; "more lines" reveals the advanced primitives.
import SwiftUI
import SwingKit

struct CoachingCanvas: View {
    let plan: OverlayPlan
    /// The drill this goal prescribes — shown on the "Drill" pill.
    var drillName: String? = nil
    /// Seek the scrubber to the fault checkpoint.
    let onSeeFix: () -> Void
    /// Open the drill's detail page.
    let onDrill: () -> Void

    @State private var showAdvanced = false

    /// The primitives actually drawn: the plan's default set, plus its advanced depth once
    /// the golfer asks for "more lines".
    private var drawn: [OverlayPrimitive] {
        showAdvanced ? plan.primitives + plan.advancedOnly : plan.primitives
    }

    var body: some View {
        VStack(spacing: 0) {
            drawing
                .frame(height: 176)
                .background(
                    RoundedRectangle(cornerRadius: Radius.inner, style: .continuous)
                        .fill(Color.ink.opacity(0.045))
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 16)

            caption
            controls
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.paper)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .floatShadow()
    }

    // MARK: - Drawing

    private var drawing: some View {
        Canvas { ctx, size in
            // Anchor everything to a "ball" near the bottom-centre of the pane.
            let ball = CGPoint(x: size.width * 0.5, y: size.height * 0.88)
            let reach = size.height * 1.5

            func end(_ angleDeg: Double, _ len: CGFloat) -> CGPoint {
                let r = angleDeg * .pi / 180
                return CGPoint(x: ball.x + cos(r) * len, y: ball.y - sin(r) * len)
            }
            func ray(_ angleDeg: Double, _ len: CGFloat) -> Path {
                var p = Path(); p.move(to: ball); p.addLine(to: end(angleDeg, len)); return p
            }

            // A faint ground line for orientation.
            var ground = Path()
            ground.move(to: CGPoint(x: 0, y: ball.y))
            ground.addLine(to: CGPoint(x: size.width, y: ball.y))
            ctx.stroke(ground, with: .color(.ink08), lineWidth: 1)

            // Corridor first (it sits behind the lines).
            for case let .targetCorridor(low, high) in drawn {
                var wedge = Path()
                wedge.move(to: ball)
                wedge.addLine(to: end(low, reach))
                wedge.addLine(to: end(high, reach))
                wedge.closeSubpath()
                ctx.fill(wedge, with: .color(.fairway.opacity(0.20)))
            }

            // Ghost of the golfer's own prior clean swing.
            for case let .ghostClub(priorAngle) in drawn {
                ctx.stroke(ray(priorAngle, reach), with: .color(.fairwayDeep.opacity(0.45)),
                           style: .init(lineWidth: 2, lineCap: .round, dash: [5, 5]))
            }

            // Held reference from address (advanced): a dashed near-vertical light line.
            for case .heldReferenceLine in drawn {
                ctx.stroke(ray(90, reach), with: .color(.bone.opacity(0.9)),
                           style: .init(lineWidth: 1.5, lineCap: .round, dash: [4, 5]))
            }

            // pathTrace is an honest advanced primitive but has no measured geometry to
            // draw yet — intentionally a no-op stub until path tracking lands.

            // The measured plane line, last so it reads on top. Brick when off-plane.
            for case let .actualPlaneLine(angle, state) in drawn {
                let off = state != .on && state != .neutral
                ctx.stroke(ray(angle, reach), with: .color(off ? .brick : .ink),
                           style: .init(lineWidth: 2.5, lineCap: .round))
            }

            // "Move here" arrow from the current line toward the ghost.
            for case let .moveArrow(fromAngle, toAngle) in drawn {
                let a = end(fromAngle, reach * 0.42)
                let b = end(toAngle, reach * 0.42)
                var arm = Path(); arm.move(to: a); arm.addLine(to: b)
                ctx.stroke(arm, with: .color(.ink70),
                           style: .init(lineWidth: 1.6, lineCap: .round))
                ctx.fill(arrowhead(at: b, from: a), with: .color(.ink70))
            }

            // The ball.
            ctx.fill(Path(ellipseIn: CGRect(x: ball.x - 4, y: ball.y - 4, width: 8, height: 8)),
                     with: .color(.ink))
        }
    }

    /// A small filled triangle pointing from `origin` toward `tip`.
    private func arrowhead(at tip: CGPoint, from origin: CGPoint) -> Path {
        let dx = tip.x - origin.x, dy = tip.y - origin.y
        let len = max(0.0001, (dx * dx + dy * dy).squareRoot())
        let ux = dx / len, uy = dy / len          // unit direction
        let size: CGFloat = 8
        let base = CGPoint(x: tip.x - ux * size, y: tip.y - uy * size)
        let px = -uy, py = ux                       // perpendicular
        var p = Path()
        p.move(to: tip)
        p.addLine(to: CGPoint(x: base.x + px * size * 0.5, y: base.y + py * size * 0.5))
        p.addLine(to: CGPoint(x: base.x - px * size * 0.5, y: base.y - py * size * 0.5))
        p.closeSubpath()
        return p
    }

    // MARK: - Caption + controls

    private var caption: some View {
        HStack {
            Text(plan.caption)
                .font(Type.display(15))
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onSeeFix) {
                    HStack(spacing: 6) {
                        PlayGlyph().fill(Color.ink).frame(width: 7, height: 8)
                        Text("See the fix")
                            .font(Type.ui(12, .medium))
                            .foregroundStyle(Color.ink)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule().strokeBorder(Color.ink25, lineWidth: 1))
                    .contentShape(Capsule())
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityIdentifier("seeFix")

                if let drillName {
                    Button(action: onDrill) {
                        Text("Drill: \(drillName) →")
                            .font(Type.ui(11, .bold))
                            .foregroundStyle(Color.fairwayText)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().fill(Color.fairway.opacity(0.16)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityIdentifier("canvasDrill")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            if !plan.advancedOnly.isEmpty {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showAdvanced.toggle()
                    }
                } label: {
                    MicroLabel(showAdvanced ? "▾ fewer lines" : "▸ more lines", color: .ink45, size: 9)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(height: 18)
            }
        }
    }
}
