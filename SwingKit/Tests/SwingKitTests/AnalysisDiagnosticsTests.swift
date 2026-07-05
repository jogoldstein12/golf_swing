import XCTest
@testable import SwingKit

final class AnalysisDiagnosticsTests: XCTestCase {
    private enum TestFailure: Error { case expected }

    func testStageDurationsAggregateRepeatedStages() {
        var diagnostics = AnalysisDiagnostics()
        diagnostics.recordStage("coarsePose", duration: 1.25)
        diagnostics.recordStage("coarsePose", duration: 0.75)
        diagnostics.recordStage("metrics", duration: 0.5)

        XCTAssertEqual(diagnostics.stageDurations["coarsePose"] ?? -1, 2, accuracy: 0.000_001)
        XCTAssertEqual(diagnostics.measuredStageDuration, 2.5, accuracy: 0.000_001)
    }

    func testFailureExportRedactsDescriptionAndPath() throws {
        let secretPath = "/private/var/mobile/secret-swing.mov"
        let error = NSError(
            domain: "UntrustedProviderError",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "Failed at \(secretPath) using sk-ant-secret"]
        )
        var diagnostics = AnalysisDiagnostics(jobID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!)
        diagnostics.recordFailure(error)

        let json = String(decoding: try diagnostics.exportedJSON(), as: UTF8.self)
        XCTAssertEqual(diagnostics.failureCategory, "other.42")
        XCTAssertFalse(json.contains(secretPath))
        XCTAssertFalse(json.contains("sk-ant-secret"))
        XCTAssertFalse(json.contains("UntrustedProviderError"))
    }

    func testThermalStateHistoryDoesNotRepeatAdjacentValues() {
        var diagnostics = AnalysisDiagnostics()
        diagnostics.recordThermalState(.nominal)
        diagnostics.recordThermalState(.nominal)
        diagnostics.recordThermalState(.serious)

        XCTAssertEqual(diagnostics.thermalStates, ["nominal", "serious"])
    }

    func testProgressIsThrottledToTenUpdatesPerSecond() {
        var throttler = AnalysisProgressThrottler(maximumUpdatesPerSecond: 10)
        let emitted = (0..<100).filter { index in
            throttler.shouldEmit(progress: Double(index) / 100, now: Double(index) / 100)
        }

        XCTAssertLessThanOrEqual(emitted.count, 10)
        XCTAssertTrue(throttler.shouldEmit(progress: 1, now: 1))
    }

    func testFailedStageRecordsDurationAndClosesInterval() async {
        var diagnostics = AnalysisDiagnostics()
        var clockValues = [4.0, 5.25].makeIterator()
        var began = false
        var ended: Bool?

        do {
            let _: Void = try await AnalysisStageTimer.measure(
                stage: "failingStage",
                diagnostics: &diagnostics,
                now: { clockValues.next()! },
                begin: { began = true },
                end: { ended = $0 }
            ) {
                throw TestFailure.expected
            }
            XCTFail("Expected stage to throw")
        } catch TestFailure.expected {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(began)
        XCTAssertEqual(ended, false)
        XCTAssertEqual(diagnostics.stageDurations["failingStage"] ?? -1, 1.25, accuracy: 0.000_001)
    }
}
