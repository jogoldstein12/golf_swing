import XCTest
@testable import SwingKit

private actor CancellationGate {
    private var isOpen = false

    func wait() async {
        while !isOpen { await Task.yield() }
    }

    func open() { isOpen = true }
}
final class CancellationTests: XCTestCase {
    func testAnalyzerPreservesPreexistingCancellation() async {
        let gate = CancellationGate()
        let task = Task {
            await gate.wait()
            return try await SwingAnalyzer.analyze(
                url: URL(fileURLWithPath: "/tmp/does-not-exist.mov"),
                view: .downTheLine
            )
        }
        task.cancel()
        await gate.open()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected; cancellation must not become SwingAnalysisFailure.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    func testCoachingServiceDoesNotFallbackAfterCancellation() async {
        let gate = CancellationGate()
        let task = Task {
            await gate.wait()
            return try await CoachingService().coach(
                CoachingRuleBasedTestsSupport.minimalReport(),
                context: .init()
            )
        }
        task.cancel()
        await gate.open()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }
}
