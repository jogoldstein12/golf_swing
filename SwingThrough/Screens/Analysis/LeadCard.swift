// The lead card — the first thing you read on the results screen: ONE finding and ONE
// action. It leads with the #1 coaching goal (title, current → target, its drill), plus
// a measured trend chip ("Fixed"/"Improving") and a delta vs your last same-club/same-
// view swing when the data supports it. When the score is insufficient, it leads instead
// with the low-confidence explanation (never a fabricated fault).
import SwiftUI
import SwingKit

struct LeadCard: View {
    let report: SwingReport
    var priorReport: SwingReport? = nil
    var history: [SwingReport] = []

    /// Whether the results screen should render a lead card at all: yes when the score
    /// is insufficient (lead with the confidence explanation) or when there is at least
    /// one coaching goal. Otherwise omit it.
    static func shouldShow(for report: SwingReport) -> Bool {
        if report.score.availability == .insufficientData { return true }
        return !(report.coaching?.goals.isEmpty ?? true)
    }

    var body: some View {
        if report.score.availability == .insufficientData {
            LowConfidenceLead(report: report)
        } else if let goal = report.coaching?.goals.first {
            goalLead(goal)
        }
    }

    private func goalLead(_ goal: CoachGoal) -> some View {
        FloatCard(padding: 24) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    MicroLabel("Your one thing")
                    Spacer()
                    trendChip(goal)
                }
                Text(goal.title)
                    .font(Type.display(26))
                    .foregroundStyle(Color.ink)
                    .padding(.top, 8)

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
                .padding(.top, 14)

                if let delta = headlineDelta(goal) {
                    DeltaBadge(delta: delta, caption: "vs last swing")
                        .padding(.top, 14)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Hairline()
                    MicroLabel("Do this next", color: .ink45)
                        .padding(.top, 10)
                    (Text(goal.drill).font(Type.ui(13, .medium))
                        + Text(" — \(goal.drillDetail)").font(Type.ui(13)))
                        .foregroundStyle(Color.ink)
                        .lineSpacing(2.5)
                }
                .padding(.top, 16)
            }
        }
        .accessibilityIdentifier("leadCard")
    }

    /// Delta of the metric this goal is grounded in, vs the prior swing. nil when there
    /// is no prior swing or the metric is withheld/absent in either report.
    private func headlineDelta(_ goal: CoachGoal) -> SwingComparison.MetricDelta? {
        guard let priorReport,
              let metric = SwingComparison.metric(for: goal, in: report) else { return nil }
        return SwingComparison.delta(for: metric.label, current: report, previous: priorReport)
    }

    @ViewBuilder
    private func trendChip(_ goal: CoachGoal) -> some View {
        switch SwingComparison.goalTrend(goal, history: history, current: report) {
        case .fixed:
            TrendChip(text: "Fixed", filled: true)
        case .improving:
            TrendChip(text: "Improving", filled: false)
        case .unchanged, .regressing, .insufficient:
            EmptyView()
        }
    }
}

/// A small measured-trend chip in the fairway accent. Only shown when backed by
/// measured data (see SwingComparison.trend).
struct TrendChip: View {
    let text: String
    var filled: Bool = false

    var body: some View {
        Text(text.uppercased())
            .font(Type.ui(9, .bold))
            .tracking(1.0)
            .foregroundStyle(Color.fairwayText)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(Color.fairway.opacity(filled ? 0.25 : 0.12)))
            .overlay(
                Capsule().strokeBorder(Color.fairway.opacity(filled ? 0 : 0.35), lineWidth: 1)
            )
    }
}

/// Signed metric change vs a prior swing. Green when it moved the right way, brick when
/// it regressed, quiet when flat.
struct DeltaBadge: View {
    let delta: SwingComparison.MetricDelta
    var caption: String

    private var color: Color {
        switch delta.improved {
        case .some(true): .fairwayText
        case .some(false): .brickText
        case .none: .ink45
        }
    }

    private var arrow: String {
        if delta.change > 0 { return "▲" }
        if delta.change < 0 { return "▼" }
        return "•"
    }

    private func magnitude(_ v: Double) -> String {
        let a = abs(v)
        return a == a.rounded() ? String(Int(a)) : String(format: "%.1f", a)
    }

    var body: some View {
        HStack(spacing: 7) {
            MicroLabel(caption, color: .ink45)
            Text("\(arrow) \(magnitude(delta.change))\(delta.unit)")
                .font(Type.ui(11, .bold))
                .foregroundStyle(color)
        }
    }
}

/// Low-confidence lead: when the read was too limited for a trustworthy score, lead
/// with why and how to get a cleaner one — never a fabricated fault or a precise score.
struct LowConfidenceLead: View {
    let report: SwingReport

    var body: some View {
        FloatCard(padding: 24) {
            VStack(alignment: .leading, spacing: 0) {
                MicroLabel("Low-confidence read", color: .brickText)
                Text("We couldn't measure this one cleanly.")
                    .font(Type.display(24))
                    .foregroundStyle(Color.ink)
                    .padding(.top, 8)

                if let warnings = report.quality?.warnings, !warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(warnings, id: \.self) { warning in
                            Text(warning)
                                .font(Type.ui(13))
                                .lineSpacing(3)
                                .foregroundStyle(Color.ink70)
                        }
                    }
                    .padding(.top, 12)
                }

                Hairline().padding(.top, 16)
                MicroLabel("How to get a cleaner read", color: .ink45)
                    .padding(.top, 12)
                Text("Frame your whole body, from head to clubhead, keep the phone steady, and shoot in even light. A down-the-line or face-on angle with the full swing in frame reads best.")
                    .font(Type.ui(13))
                    .lineSpacing(3)
                    .foregroundStyle(Color.ink45)
                    .padding(.top, 6)
            }
        }
        .accessibilityIdentifier("lowConfidenceLead")
    }
}
