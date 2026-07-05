import Foundation
import Observation
import SwingKit

@Observable
@MainActor
final class EnhancedCoachingStore {
    enum State: Equatable {
        case local
        case enhancing
        case enhanced
    }

    static let shared = EnhancedCoachingStore()

    private(set) var states: [UUID: State] = [:]
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]

    func state(for reportID: UUID) -> State {
        states[reportID] ?? .local
    }

    func enhance(_ model: AnalysisModel) async {
        let reportID = model.report.id
        guard tasks[reportID] == nil,
              state(for: reportID) == .local,
              AppAPIKeyProvider().apiKey() != nil
        else { return }

        states[reportID] = .enhancing
        let snapshot = model.report
        let task = Task { @MainActor in
            defer { tasks[reportID] = nil }
            do {
                let plan = try await CoachingService(apiKeyProvider: AppAPIKeyProvider())
                    .enhancedCoach(
                        snapshot,
                        context: CoachingContext(club: snapshot.club)
                    )
                try Task.checkCancellation()
                guard model.report.id == reportID else { return }
                model.applyEnhancedCoaching(plan)
                if model.report.videoFileName != nil {
                    _ = try? SwingStore.saveReport(model.report)
                }
                states[reportID] = .enhanced
            } catch {
                states[reportID] = .local
            }
        }
        tasks[reportID] = task
        await task.value
    }

    func cancel(reportID: UUID) {
        tasks[reportID]?.cancel()
        tasks[reportID] = nil
        if states[reportID] == .enhancing { states[reportID] = .local }
    }
}
