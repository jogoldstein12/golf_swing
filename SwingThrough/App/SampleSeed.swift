// Restoring the bundled sample swing into the gallery. The sample video lives in the app
// bundle (Fixtures/sample_dtl.mp4) and is never deleted by "clear local data" — only its
// gallery *record* is. This one idempotent entry point re-inserts that record so the
// sample can always be brought back: on a fresh/empty gallery, right after a delete-all,
// or explicitly from Settings.
import Foundation
import SwiftData

enum SampleSeed {

    /// Insert the bundled sample swing's gallery record if it isn't already present, and
    /// persist it. Idempotent — safe to call repeatedly. Returns false only when the
    /// bundled sample itself can't be loaded (a build/packaging problem), so callers can
    /// surface an honest "sample unavailable" state instead of a silent no-op.
    @MainActor
    @discardableResult
    static func ensure(in context: ModelContext) -> Bool {
        guard let demo = DemoData.load()?.report else { return false }

        let sampleID = demo.id
        let existing = FetchDescriptor<SwingRecord>(
            predicate: #Predicate { $0.id == sampleID }
        )
        if let found = try? context.fetch(existing), !found.isEmpty { return true }

        let record = SwingRecord(
            id: demo.id, date: demo.date, club: demo.club, score: demo.score.total,
            viewRaw: demo.view.rawValue, reportFileName: "", videoFileName: nil,
            isSample: true
        )
        context.insert(record)
        try? context.save()
        return true
    }
}
