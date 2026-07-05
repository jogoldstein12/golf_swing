import XCTest
import SwingKit
@testable import SwingThrough

@MainActor
final class DiagnosticsStoreTests: XCTestCase {
    func testFinishedSnapshotCannotBeOverwrittenByLateProgress() {
        let jobID = UUID()
        let store = DiagnosticsStore.shared
        store.begin(jobID: jobID)

        var finished = AnalysisDiagnostics(jobID: jobID, stageDurations: ["metrics": 1])
        finished.finish()
        store.update(finished)
        store.update(AnalysisDiagnostics(jobID: jobID))

        XCTAssertEqual(store.latest?.jobID, jobID)
        XCTAssertNotNil(store.latest?.finishedAt)
        XCTAssertEqual(store.latest?.stageDurations["metrics"], 1)
    }

    func testPreviousJobCannotOverwriteActiveJob() {
        let activeID = UUID()
        let staleID = UUID()
        let store = DiagnosticsStore.shared
        store.begin(jobID: activeID)
        store.update(AnalysisDiagnostics(jobID: activeID, stageDurations: ["preflight": 0.1]))
        store.update(AnalysisDiagnostics(jobID: staleID, stageDurations: ["metrics": 2]))

        XCTAssertEqual(store.latest?.jobID, activeID)
        XCTAssertNil(store.latest?.stageDurations["metrics"])
    }
}
