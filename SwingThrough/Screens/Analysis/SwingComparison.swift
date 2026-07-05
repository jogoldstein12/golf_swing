// Pure, unit-testable comparison + trend logic over SwingReports. No IO, no view
// types, no DB access — RootView resolves the prior/history reports from SwiftData and
// passes them in. The measurement layer stays the single source of truth: a delta or a
// trend is only ever computed from MEASURED values. A withheld metric
// (provenance == .unavailable) or an unavailable score never participates.
import Foundation
import SwingKit

enum SwingComparison {

    /// A signed change in one metric between a prior and the current swing. Carries the
    /// ideal band so "did it improve?" can be answered for band-centered metrics too.
    struct MetricDelta: Equatable {
        let label: String
        let unit: String
        let previous: Double
        let current: Double
        let idealLow: Double
        let idealHigh: Double
        let higherIsBetter: Bool?

        var change: Double { current - previous }
        var currentInBand: Bool { current >= idealLow && current <= idealHigh }

        /// true = moved the right way, false = worse, nil = no change. For
        /// band-centered metrics (higherIsBetter == nil) "the right way" is toward the
        /// ideal band.
        var improved: Bool? {
            if change == 0 { return nil }
            if let higherIsBetter { return higherIsBetter ? change > 0 : change < 0 }
            let dPrev = Self.distanceToBand(previous, low: idealLow, high: idealHigh)
            let dCur = Self.distanceToBand(current, low: idealLow, high: idealHigh)
            if dCur == dPrev { return nil }
            return dCur < dPrev
        }

        static func distanceToBand(_ v: Double, low: Double, high: Double) -> Double {
            if v < low { return low - v }
            if v > high { return v - high }
            return 0
        }
    }

    /// The metric with `label`, but only when it was actually measured: present,
    /// finite, and not withheld (provenance != .unavailable). A nil quality is treated
    /// as measured — legacy reports predate provenance tagging.
    static func measuredMetric(_ label: String, in report: SwingReport) -> MetricValue? {
        guard let m = report.metrics.first(where: { $0.label == label }) else { return nil }
        if m.quality?.provenance == .unavailable { return nil }
        guard m.value.isFinite else { return nil }
        return m
    }

    /// Signed delta for one metric label between two reports. Returns nil when the
    /// metric is missing from either report OR when either side is withheld — never
    /// compute a delta against an un-measured value.
    static func delta(for label: String, current: SwingReport, previous: SwingReport) -> MetricDelta? {
        guard let c = measuredMetric(label, in: current),
              let p = measuredMetric(label, in: previous) else { return nil }
        return MetricDelta(
            label: c.label, unit: c.unit, previous: p.value, current: c.value,
            idealLow: c.idealLow, idealHigh: c.idealHigh, higherIsBetter: c.higherIsBetter
        )
    }

    /// Signed score change. Returns nil when either score is unavailable (insufficient
    /// data) — a withheld score is never differenced.
    static func scoreDelta(current: SwingReport, previous: SwingReport) -> Int? {
        guard current.score.isAvailable, previous.score.isAvailable else { return nil }
        return current.score.total - previous.score.total
    }

    // MARK: - Goal ↔ metric resolution

    /// Resolve which measured metric a coaching goal is grounded in. Goals name their
    /// metric editorially ("Swing plane at P5"); metrics are labelled tersely
    /// ("Swing Plane"). Match on a normalized exact-then-containment basis so a trend
    /// chip only ever appears when there is a real measured metric behind the goal.
    static func metric(for goal: CoachGoal, in report: SwingReport) -> MetricValue? {
        let key = normalize(goal.metricLabel)
        guard !key.isEmpty else { return nil }
        if let exact = report.metrics.first(where: { normalize($0.label) == key }) {
            return exact
        }
        return report.metrics.first { m in
            let k = normalize(m.label)
            guard !k.isEmpty else { return false }
            return key.contains(k) || k.contains(key)
        }
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    // MARK: - Fault-fixed / improving detection (B4)

    enum Trend: Equatable {
        case fixed        // held inside the ideal band for `streak` consecutive measured swings
        case improving    // moving toward the band, not yet held
        case unchanged
        case regressing
        case insufficient // not enough measured samples to judge
    }

    /// N — how many of the most recent same-club swings to consider.
    static let trendWindow = 5
    /// M — consecutive in-band measured swings required to call a fault "fixed".
    static let fixedStreak = 2

    /// Trend of a single metric across an ordered history.
    ///
    /// `history` MUST be in chronological order (oldest first, newest last) and contain
    /// ONLY same-club swings; the current swing is expected to be the last element.
    /// Only MEASURED values participate — withheld/absent samples are skipped entirely,
    /// so they neither confirm nor break a streak (MEASURED trends only, per spec).
    static func trend(for label: String, history: [SwingReport],
                      window: Int = trendWindow, streak: Int = fixedStreak) -> Trend {
        let samples = history.suffix(window).compactMap { measuredMetric(label, in: $0) }
        guard samples.count >= streak else { return .insufficient }
        if samples.suffix(streak).allSatisfy({ $0.inBand }) { return .fixed }
        guard let first = samples.first, let last = samples.last else { return .insufficient }
        let d0 = MetricDelta.distanceToBand(first.value, low: first.idealLow, high: first.idealHigh)
        let d1 = MetricDelta.distanceToBand(last.value, low: last.idealLow, high: last.idealHigh)
        if d1 < d0 { return .improving }
        if d1 > d0 { return .regressing }
        return .unchanged
    }

    /// Trend of the metric a goal is grounded in, across `history`. `.insufficient`
    /// when the goal has no resolvable measured metric.
    static func goalTrend(_ goal: CoachGoal, history: [SwingReport],
                          current: SwingReport) -> Trend {
        guard let metric = metric(for: goal, in: current) else { return .insufficient }
        return trend(for: metric.label, history: history)
    }
}
