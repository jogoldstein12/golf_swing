// WS-E follow-up (NP-1): the other half of the pinned-focus loop. A `FocusRecord` is
// pinned from a coaching goal; this closes the loop by verifying, on the very next
// same-club/same-view swings, whether the metric it names has actually held inside its
// ideal band for `SwingComparison.fixedStreak` consecutive MEASURED swings. Only a real
// measured trend resolves a focus — a withheld metric never confirms or denies it.
import Foundation
import SwiftData
import SwingKit

enum FocusResolver {

    /// Pure predicate: has the focus's metric gone `.fixed` across `history` (which MUST
    /// include `current` as its last, newest element, chronological oldest→newest, per
    /// `SwingComparison.trend`'s contract)?
    static func shouldResolve(focus: FocusRecord, history: [SwingReport], current: SwingReport) -> Bool {
        SwingComparison.trend(for: focus.metricLabel, history: history) == .fixed
    }

    /// Side-effecting: look for an unresolved focus matching `record`'s (club, view),
    /// build its recent measured history from `history` (same-club/same-view,
    /// non-sample, newest `trendWindow` records, oldest→newest), append `currentReport`,
    /// and resolve the focus when the trend reads `.fixed`. Best-effort: any missing
    /// report, absent focus, or short history is a silent no-op — never throws into the
    /// caller's save path.
    static func resolve(current record: SwingRecord, currentReport: SwingReport,
                        history: [SwingRecord], context: ModelContext) {
        let club = record.club, viewRaw = record.viewRaw
        let descriptor = FetchDescriptor<FocusRecord>(
            predicate: #Predicate { $0.resolvedSwingID == nil && $0.club == club && $0.viewRaw == viewRaw }
        )
        guard let matches = try? context.fetch(descriptor), let focus = matches.first else { return }

        let priorRecords = history
            .filter { $0.club == club && $0.viewRaw == viewRaw && !$0.isSample && $0.id != record.id }
            .sorted { $0.date < $1.date }
            .suffix(SwingComparison.trendWindow - 1)

        let priorReports = priorRecords.compactMap { SwingStore.loadReport(named: $0.reportFileName) }
        let reportHistory = priorReports + [currentReport]

        guard shouldResolve(focus: focus, history: reportHistory, current: currentReport) else { return }
        focus.resolvedSwingID = record.id
        try? context.save()
    }
}
