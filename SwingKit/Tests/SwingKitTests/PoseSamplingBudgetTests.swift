import XCTest
@testable import SwingKit

final class PoseSamplingBudgetTests: XCTestCase {
    func testFiveSecondSourceIsBoundedIndependentOfNativeFrameRate() {
        XCTAssertEqual(PoseSamplingBudget.maximumSampleCount(duration: 5, sampleFPS: 12), 61)
        XCTAssertEqual(PoseSamplingBudget.maximumSampleCount(duration: 5, sampleFPS: 30), 151)
    }

    func testInvalidSamplingInputsProduceNoRequests() {
        XCTAssertEqual(PoseSamplingBudget.maximumSampleCount(duration: 0, sampleFPS: 30), 0)
        XCTAssertEqual(PoseSamplingBudget.maximumSampleCount(duration: 5, sampleFPS: 0), 0)
    }

    func testRequestedWindowIsClampedToSourceDuration() {
        XCTAssertEqual(SwingAnalyzer.normalizedWindow(2...8, duration: 5), 2...5)
        XCTAssertEqual(SwingAnalyzer.normalizedWindow(-2...3, duration: 5), 0...3)
        XCTAssertEqual(SwingAnalyzer.normalizedWindow(4.9...5, duration: 5), 0...5)
    }

    func testIntermittentFrameFailuresStayWithinBudget() {
        XCTAssertFalse(PoseFailureBudget(
            attempted: 20, failed: 2, consecutiveFailures: 1
        ).shouldAbort)
        XCTAssertTrue(PoseFailureBudget(
            attempted: 20, failed: 3, consecutiveFailures: 1
        ).shouldAbort)
        XCTAssertTrue(PoseFailureBudget(
            attempted: 8, failed: 6, consecutiveFailures: 6
        ).shouldAbort)
    }
}
