// Shown while the measurement pipeline runs on a fresh capture. The motif is the
// instrument at work: a fairway point sweeping the swing-plane ellipse, phase
// micro-labels, and a hairline progress line. All animation is TimelineView-driven.
import SwiftUI

struct AnalyzingScreen: View {
    var progress: Double            // 0…1 from the analyzer
    var phase: String               // "Reading motion", "Measuring the plane", …

    var body: some View {
        ZStack {
            Color.bone.grain().ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()

                TimelineView(.animation) { context in
                    Canvas { ctx, size in
                        let t = context.date.timeIntervalSinceReferenceDate
                        let cx = size.width / 2, cy = size.height / 2
                        let rx = size.width * 0.36, ry = rx * 0.42
                        let tilt = -28.0 * .pi / 180

                        func pt(_ theta: Double) -> CGPoint {
                            let x = rx * cos(theta), y = ry * sin(theta)
                            return CGPoint(x: cx + x * cos(tilt) - y * sin(tilt),
                                           y: cy + x * sin(tilt) + y * cos(tilt))
                        }

                        // The plane disc
                        var ellipse = Path()
                        ellipse.move(to: pt(0))
                        for i in 1...240 { ellipse.addLine(to: pt(Double(i) / 240 * 2 * .pi)) }
                        ellipse.closeSubpath()
                        ctx.stroke(ellipse, with: .color(.ink25), lineWidth: 1)

                        // Sweeping measurement point + fading trail
                        let head = t * 1.9
                        for i in 0..<26 {
                            let theta = head - Double(i) * 0.055
                            let p = pt(theta)
                            let a = pow(1 - Double(i) / 26, 2.2)
                            let r = 3.6 * (1 - Double(i) / 30)
                            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                                     with: .color(.fairwayDeep.opacity(a)))
                        }
                    }
                }
                .frame(height: 220)
                .padding(.horizontal, 24)

                Text("Measuring your swing.")
                    .font(Type.display(28))
                    .foregroundStyle(Color.ink)
                    .padding(.top, 26)

                MicroLabel(phase, color: .ink45)
                    .padding(.top, 12)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: phase)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.ink08).frame(height: 2)
                        Capsule().fill(Color.fairwayDeep)
                            .frame(width: max(4, geo.size.width * progress), height: 2)
                            .animation(.easeOut(duration: 0.4), value: progress)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(height: 20)
                .padding(.horizontal, 80)
                .padding(.top, 22)

                Spacer()

                Text("Everything is measured on this phone.")
                    .font(Type.displayItalic(15))
                    .foregroundStyle(Color.ink25)
                    .padding(.bottom, 36)
            }
        }
    }
}

private struct AnalyzingScreen_Previews: PreviewProvider {
    static var previews: some View {
        AnalyzingScreen(progress: 0.4, phase: "Measuring the plane")
    }
}
