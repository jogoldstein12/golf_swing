// WS-E — the calm top summary band. The score is present but quiet; the loud thing is
// "your one thing" (goal #1) with a measured delta vs the last swing. When the read was
// too limited for a trustworthy total it says so plainly — never a fabricated number.
import SwiftUI
import SwingKit

struct GlanceStrip: View {
    let score: SwingScore
    /// Goal #1's title — the single thing to work on. nil when there is no coaching plan.
    var oneThing: String?
    /// Signed score change vs the prior same-club/same-view swing, or nil when there is none.
    var scoreDelta: Int?

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            scoreSide
            if oneThing != nil {
                Rectangle()
                    .fill(Color.ink08)
                    .frame(width: 1, height: 40)
                oneThingSide
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Hairline() }
        .background(Color.bone)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("glanceStrip")
    }

    private var scoreSide: some View {
        VStack(alignment: .leading, spacing: 3) {
            MicroLabel("Score", color: .ink45, size: 9)
            if score.isAvailable {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(score.total)")
                        .font(Type.display(20))
                        .foregroundStyle(Color.ink)
                    Text("/100")
                        .font(Type.display(11))
                        .foregroundStyle(Color.ink25)
                }
            } else {
                Text("Not scored — low-confidence read")
                    .font(Type.ui(11.5, .medium))
                    .foregroundStyle(Color.ink70)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 150, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var oneThingSide: some View {
        if let oneThing {
            VStack(alignment: .leading, spacing: 3) {
                MicroLabel("Your one thing", color: .ink45, size: 9)
                Text(oneThing)
                    .font(Type.display(13))
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let scoreDelta {
                    deltaLine(scoreDelta)
                }
            }
        }
    }

    private func deltaLine(_ value: Int) -> some View {
        let color: Color = value > 0 ? .fairwayText : value < 0 ? .brickText : .ink45
        let arrow = value > 0 ? "▲" : value < 0 ? "▼" : "•"
        let sign = value > 0 ? "+" : ""
        return Text("\(arrow) \(sign)\(value) vs last swing")
            .font(Type.ui(10, .bold))
            .foregroundStyle(color)
    }
}
