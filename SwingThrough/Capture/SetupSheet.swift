// "How to set up" — one editorial page per capture angle. Accuracy depends on setup,
// so this copy is part of the measurement system, not marketing.
import SwiftUI
import SwingKit

struct SetupSheet: View {
    let angle: CaptureView
    @Environment(\.dismiss) private var dismiss

    private struct Step {
        let title: String
        let detail: String
    }

    private var steps: [Step] {
        switch angle {
        case .faceOn:
            [
                Step(title: "Camera at hand height",
                     detail: "Prop the phone about ten feet (3 m) away, square to "
                        + "your chest, lens at the height of your hands at address."),
                Step(title: "Fill the guide",
                     detail: "Stand centered with both feet on the ground line. Your "
                        + "whole body — cap to spikes — stays inside the frame through "
                        + "the finish."),
                Step(title: "Plain, even background",
                     detail: "A clean backdrop and even light keep the joint tracking "
                        + "honest. Avoid strong backlight."),
                Step(title: "Then just swing",
                     detail: "Recording is automatic: hold your address about a second "
                        + "to arm, and the swing is captured on its own at high frame "
                        + "rate."),
            ]
        default:
            [
                Step(title: "Camera down the line",
                     detail: "Prop the phone about ten feet (3 m) behind your hands, "
                        + "looking straight down the target line, lens at hand height."),
                Step(title: "Fill the guide",
                     detail: "Address the ball so your body fills the zone and your "
                        + "feet sit on the ground line. The target line hint should "
                        + "run out ahead of the ball."),
                Step(title: "Plain, even background",
                     detail: "A clean backdrop and even light keep the joint tracking "
                        + "honest. Avoid strong backlight."),
                Step(title: "Then just swing",
                     detail: "Recording is automatic: hold your address about a second "
                        + "to arm, and the swing is captured on its own at high frame "
                        + "rate."),
            ]
        }
    }

    var body: some View {
        ZStack {
            Color.bone.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        MicroLabel("How to set up")
                        Text(angle == .downTheLine ? "Down the line" : "Face on")
                            .font(Type.display(32))
                            .foregroundStyle(Color.ink)
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        ZStack {
                            Circle().strokeBorder(Color.ink25, lineWidth: 1)
                            CrossGlyph()
                                .stroke(Color.ink70, style: StrokeStyle(
                                    lineWidth: 1.3, lineCap: .round))
                                .frame(width: 10, height: 10)
                        }
                        .frame(width: 34, height: 34)
                        .contentShape(Circle())
                    }
                    .buttonStyle(PressScaleStyle())
                }

                Text(angle == .downTheLine
                     ? "The camera looks along your target line — this is the view "
                       + "that reveals swing plane."
                     : "The camera faces your chest — this is the view that reveals "
                       + "turn, sway, and tempo.")
                    .font(Type.displayItalic(17))
                    .foregroundStyle(Color.ink70)
                    .padding(.top, 14)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                        if i > 0 { Hairline() }
                        HStack(alignment: .top, spacing: 16) {
                            Text("\(i + 1)")
                                .font(Type.display(26))
                                .foregroundStyle(Color.ink25)
                                .frame(width: 22, alignment: .leading)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(step.title)
                                    .font(Type.ui(14, .medium))
                                    .foregroundStyle(Color.ink)
                                Text(step.detail)
                                    .font(Type.ui(12.5))
                                    .lineSpacing(3.5)
                                    .foregroundStyle(Color.ink70)
                            }
                        }
                        .padding(.vertical, 16)
                    }
                }
                .padding(.top, 14)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 26)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color.bone)
    }
}

private struct SetupSheet_Previews: PreviewProvider {
    static var previews: some View { SetupSheet(angle: .downTheLine) }
}
