import XCTest
import SwingKit
@testable import SwingThrough

private actor BlockingSwingAnalyzer: SwingAnalyzing {
    func analyze(
        request: AnalysisJobRequest,
        progress: @escaping @Sendable (Double) -> Void,
        diagnostics: @escaping @Sendable (AnalysisDiagnostics) -> Void
    ) async throws -> SwingAnalysisResult {
        progress(0.2)
        while true {
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
}

final class AnalysisJobCoordinatorTests: XCTestCase {
    func testCancelStopsMatchingActiveJob() async throws {
        let coordinator = AnalysisJobCoordinator(analyzer: BlockingSwingAnalyzer())
        let request = makeRequest()
        let task = Task {
            try await coordinator.run(
                request: request,
                progress: { _ in },
                diagnostics: { _ in }
            )
        }
        try await waitUntilActive(coordinator, jobID: request.jobID)

        let didCancel = await coordinator.cancel(
            jobID: request.jobID,
            executionID: request.executionID
        )
        XCTAssertTrue(didCancel)
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }
        let activeAfterCancel = await coordinator.activeJob()
        XCTAssertNil(activeAfterCancel)
    }

    func testSecondJobCannotReplaceActiveJob() async throws {
        let coordinator = AnalysisJobCoordinator(analyzer: BlockingSwingAnalyzer())
        let first = makeRequest()
        let firstTask = Task {
            try await coordinator.run(
                request: first,
                progress: { _ in },
                diagnostics: { _ in }
            )
        }
        try await waitUntilActive(coordinator, jobID: first.jobID)

        let second = makeRequest()
        do {
            _ = try await coordinator.run(
                request: second,
                progress: { _ in },
                diagnostics: { _ in }
            )
            XCTFail("Expected active-job rejection")
        } catch let error as AnalysisJobCoordinatorError {
            XCTAssertEqual(error, .jobAlreadyActive(first.jobID))
        }
        let activeAfterRejection = await coordinator.activeJob()
        XCTAssertEqual(activeAfterRejection, first.jobID)

        _ = await coordinator.cancel(jobID: first.jobID, executionID: first.executionID)
        _ = try? await firstTask.value
    }

    func testStaleExecutionCannotCancelRetry() async throws {
        let coordinator = AnalysisJobCoordinator(analyzer: BlockingSwingAnalyzer())
        let request = makeRequest()
        let task = Task {
            try await coordinator.run(
                request: request,
                progress: { _ in },
                diagnostics: { _ in }
            )
        }
        try await waitUntilActive(coordinator, jobID: request.jobID)

        let staleCancelled = await coordinator.cancel(
            jobID: request.jobID,
            executionID: UUID()
        )
        XCTAssertFalse(staleCancelled)
        let activeAfterStaleCancel = await coordinator.activeJob()
        XCTAssertEqual(activeAfterStaleCancel, request.jobID)

        _ = await coordinator.cancel(jobID: request.jobID, executionID: request.executionID)
        _ = try? await task.value
    }

    private func makeRequest() -> AnalysisJobRequest {
        AnalysisJobRequest(
            jobID: UUID(),
            executionID: UUID(),
            videoURL: URL(fileURLWithPath: "/tmp/test.mov"),
            view: .downTheLine,
            sourceWindow: 1...6,
            handednessOverride: .left
        )
    }

    private func waitUntilActive(_ coordinator: AnalysisJobCoordinator,
                                 jobID: UUID) async throws {
        for _ in 0..<100 {
            if await coordinator.activeJob() == jobID { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Coordinator never became active")
    }
}
