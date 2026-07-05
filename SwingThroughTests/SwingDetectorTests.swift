import XCTest
@testable import SwingThrough

final class SwingDetectorTests: XCTestCase {
    func testManualCaptureDoesNotFinishBeforeMotion() {
        let detector = SwingDetector()
        detector.config.settleHold = 0.25
        detector.config.maxCapture = 3
        let start = input(time: 0, source: 0, gripX: 0.5)
        _ = detector.beginManualCapture(input: start)

        var events: [SwingDetector.Event] = []
        for index in 1...15 {
            events += detector.ingest(input(
                time: Double(index) * 0.1,
                source: Double(index) * 0.1,
                gripX: 0.5
            ))
        }

        XCTAssertFalse(events.contains { event in
            if case .captured = event { return true }
            return false
        })
    }

    func testManualCaptureTimesOutInsteadOfSavingSwinglessClip() {
        let detector = SwingDetector()
        detector.config.maxCapture = 0.5
        _ = detector.beginManualCapture(input: input(time: 0, source: 0, gripX: 0.5))

        let events = detector.ingest(input(time: 0.6, source: 0.6, gripX: 0.5))

        XCTAssertTrue(events.contains(.recordCancel))
        XCTAssertTrue(events.contains(.disarmed(.timeout)))
        XCTAssertFalse(events.contains { event in
            if case .captured = event { return true }
            return false
        })
    }

    private func input(time: Double, source: Double, gripX: Double) -> SwingDetector.Input {
        SwingDetector.Input(
            time: time,
            sourceTime: source,
            grip: .init(gripX, 0.5),
            hipCenterX: 0.5,
            spineFromVerticalDeg: 35,
            checklistGreen: true,
            requirePosture: false
        )
    }
}
