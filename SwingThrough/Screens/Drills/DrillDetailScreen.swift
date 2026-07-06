// WS-E — the practice-loop page. One goal, one cue, one drill, one commitment. Tapping
// "Work on this" pins a FocusRecord for this (club, view) — the thing the golfer carries
// into the next swing — replacing any earlier unresolved focus so only one is ever active.
import SwiftData
import SwiftUI
import SwingKit

struct DrillDetailScreen: View {
    let goal: CoachGoal
    let club: String
    let viewRaw: String
    var onBack: () -> Void = {}
    var onDone: () -> Void = {}

    @Environment(\.modelContext) private var context

    /// The external-focus cue leads; fall back to the goal title for older reports.
    private var cue: String { goal.cue ?? goal.title }

    var body: some View {
        ZStack {
            Color.bone.grain().ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    VStack(alignment: .leading, spacing: 8) {
                        MicroLabel("Practice this")
                        Text(cue)
                            .font(Type.display(34))
                            .foregroundStyle(Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 36)

                    currentTarget.padding(.top, 24)

                    drillCard.padding(.top, 20)

                    whyItWorks.padding(.top, 20)

                    PrimaryButton("Work on this", action: commit)
                        .padding(.top, 32)
                        .accessibilityIdentifier("workOnThis")

                    Text("We'll pin this to your \(club) and check it on your next swing.")
                        .font(Type.ui(12))
                        .foregroundStyle(Color.ink45)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 14)
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 40)
            }
        }
    }

    private var header: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 9) {
                    ZStack {
                        Circle().strokeBorder(Color.ink25, lineWidth: 1)
                        ChevronGlyph(pointsRight: false)
                            .stroke(Color.ink70, style: .init(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                            .frame(width: 6, height: 11)
                    }
                    .frame(width: 32, height: 32)
                    MicroLabel("Analysis", color: .ink70)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())
            Spacer()
            MicroLabel(club, color: .ink70)
        }
    }

    private var currentTarget: some View {
        HStack(spacing: 12) {
            Text(goal.current)
                .font(Type.ui(11, .medium))
                .foregroundStyle(Color.ink70)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Capsule().fill(Color.sand))
            Text("→")
                .font(Type.ui(12))
                .foregroundStyle(Color.ink25)
            Text(goal.target)
                .font(Type.ui(11, .bold))
                .foregroundStyle(Color.fairwayText)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Capsule().fill(Color.fairway.opacity(0.2)))
        }
    }

    private var drillCard: some View {
        FloatCard(padding: 24) {
            VStack(alignment: .leading, spacing: 8) {
                MicroLabel("The drill", color: .fairwayText)
                Text(goal.drill)
                    .font(Type.display(24))
                    .foregroundStyle(Color.ink)
                Text(goal.drillDetail)
                    .font(Type.ui(14))
                    .lineSpacing(4)
                    .foregroundStyle(Color.ink70)
                    .padding(.top, 2)
            }
        }
    }

    private var whyItWorks: some View {
        FloatCard(padding: 24) {
            VStack(alignment: .leading, spacing: 10) {
                MicroLabel("Why it works", color: .ink45)
                Text(goal.detail)
                    .font(Type.ui(13.5))
                    .lineSpacing(3.5)
                    .foregroundStyle(Color.ink70)
            }
        }
    }

    // MARK: - Commit

    /// Pin this focus for the current (club, view). At most one unresolved focus per
    /// (club, view) — clear any earlier one first, then insert and hand back.
    private func commit() {
        let club = self.club, viewRaw = self.viewRaw
        let descriptor = FetchDescriptor<FocusRecord>(
            predicate: #Predicate { $0.resolvedSwingID == nil && $0.club == club && $0.viewRaw == viewRaw }
        )
        if let existing = try? context.fetch(descriptor) {
            for record in existing { context.delete(record) }
        }
        context.insert(FocusRecord(
            club: club,
            viewRaw: viewRaw,
            goalTitle: goal.title,
            metricLabel: goal.metricLabel,
            cue: goal.cue ?? goal.title,
            drillName: goal.drill
        ))
        try? context.save()
        onDone()
    }
}
