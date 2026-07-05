// The end-to-end run for a fresh capture: measure → coach → persist. UI-facing state
// for the Analyzing screen lives here; the math lives in SwingKit.
import Foundation
import Observation
import SwiftData
import SwingKit

@Observable
@MainActor
final class SwingSession {
    enum Phase {
        case idle
        case running(progress: Double, label: String)
        case failed(String)
    }

    var phase: Phase = .idle

    /// Analyze a captured clip end to end. Returns the stored record on success.
    func run(url: URL, view: CaptureView, club: String,
             context: ModelContext, history: [SwingRecord]) async -> SwingRecord? {
        phase = .running(progress: 0, label: "Reading motion")
        do {
            let report = try await SwingAnalyzer.analyze(url: url, view: view) { p in
                Task { @MainActor [weak self] in
                    self?.phase = .running(progress: p, label: Self.label(for: p))
                }
            }

            var finished = report
            finished.club = club

            self.phase = .running(progress: 1.0, label: "Writing your coaching")
            let recentTitles = history.prefix(3)
                .compactMap { SwingStore.loadReport(named: $0.reportFileName)?.coaching }
                .flatMap { $0.goals.map(\.title) }
            let coaching = await CoachingService(apiKeyProvider: AppAPIKeyProvider())
                .coach(finished, context: CoachingContext(club: club, recentGoalTitles: recentTitles))
            finished.coaching = coaching

            let videoName = try SwingStore.adoptVideo(at: url, id: finished.id)
            finished.videoFileName = videoName
            let reportName = try SwingStore.saveReport(finished)

            let record = SwingRecord(
                id: finished.id, date: finished.date, club: finished.club,
                score: finished.score.total, viewRaw: finished.view.rawValue,
                reportFileName: reportName, videoFileName: videoName
            )
            context.insert(record)
            try context.save()
            phase = .idle
            return record
        } catch {
            phase = .failed(error.localizedDescription)
            return nil
        }
    }

    private static func label(for p: Double) -> String {
        switch p {
        case ..<0.25: "Reading motion"
        case ..<0.75: "Tracking your body in 3D"
        case ..<0.85: "Finding your checkpoints"
        case ..<0.95: "Measuring plane and sequence"
        default: "Scoring the swing"
        }
    }
}
