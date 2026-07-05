import Foundation
import SwingKit

protocol SwingAnalyzing: Sendable {
    func analyze(
        request: AnalysisJobRequest,
        progress: @escaping @Sendable (Double) -> Void,
        diagnostics: @escaping @Sendable (AnalysisDiagnostics) -> Void
    ) async throws -> SwingAnalysisResult
}

struct LiveSwingAnalyzer: SwingAnalyzing {
    func analyze(
        request: AnalysisJobRequest,
        progress: @escaping @Sendable (Double) -> Void,
        diagnostics: @escaping @Sendable (AnalysisDiagnostics) -> Void
    ) async throws -> SwingAnalysisResult {
        try await SwingAnalyzer.analyzeWithDiagnostics(
            url: request.videoURL,
            view: request.view,
            sourceWindow: request.sourceWindow,
            handednessOverride: request.handednessOverride,
            jobID: request.jobID,
            diagnostics: diagnostics,
            progress: progress
        )
    }
}

enum AnalysisJobCoordinatorError: LocalizedError, Equatable {
    case jobAlreadyActive(UUID)

    var errorDescription: String? {
        switch self {
        case .jobAlreadyActive:
            "Another swing is already being analyzed. Cancel it or wait for it to finish."
        }
    }
}

actor AnalysisJobCoordinator {
    private let analyzer: any SwingAnalyzing
    private var activeJobID: UUID?
    private var activeExecutionID: UUID?
    private var activeTask: Task<SwingAnalysisResult, Error>?

    init(analyzer: any SwingAnalyzing = LiveSwingAnalyzer()) {
        self.analyzer = analyzer
    }

    func run(
        request: AnalysisJobRequest,
        progress: @escaping @Sendable (Double) -> Void,
        diagnostics: @escaping @Sendable (AnalysisDiagnostics) -> Void
    ) async throws -> SwingAnalysisResult {
        if let activeJobID {
            throw AnalysisJobCoordinatorError.jobAlreadyActive(activeJobID)
        }

        let task = Task {
            try await analyzer.analyze(
                request: request,
                progress: progress,
                diagnostics: diagnostics
            )
        }
        activeJobID = request.jobID
        activeExecutionID = request.executionID
        activeTask = task

        defer {
            if activeExecutionID == request.executionID {
                activeTask = nil
                activeJobID = nil
                activeExecutionID = nil
            }
        }
        return try await task.value
    }

    @discardableResult
    func cancel(jobID: UUID, executionID: UUID) -> Bool {
        guard activeJobID == jobID, activeExecutionID == executionID else { return false }
        activeTask?.cancel()
        return true
    }

    func activeJob() -> UUID? {
        activeJobID
    }
}
