// NP-3 — SequencePresentation.isTrustworthy gates the power-staircase panel's confident
// order verdict. It must refuse to claim order on an incomplete, low-confidence, or
// degenerate read, and allow it only for a clean, complete, resolvable one.
import XCTest
import SwingKit
@testable import SwingThrough

final class SequencePresentationTests: XCTestCase {

    private func peaks(pelvisTime: Double = 0.10, torsoTime: Double = 0.26) -> [KinematicSequence.Peak] {
        [
            .init(segment: .pelvis, time: pelvisTime, peakDegPerSec: 480),
            .init(segment: .torso, time: torsoTime, peakDegPerSec: 640),
            .init(segment: .leadArm, time: torsoTime + 0.05, peakDegPerSec: 790),
            .init(segment: .club, time: torsoTime + 0.12, peakDegPerSec: 2100),
        ]
    }

    func testTrustworthyForACleanFourPeakNonDegenerateSequence() {
        let seq = KinematicSequence(peaks: peaks())
        XCTAssertTrue(SequencePresentation.isTrustworthy(seq))
    }

    func testNotTrustworthyWhenLowConfidence() {
        let seq = KinematicSequence(peaks: peaks(), lowConfidence: true)
        XCTAssertFalse(SequencePresentation.isTrustworthy(seq))
    }

    func testNotTrustworthyWhenDegenerate() {
        // Pelvis and torso within the sub-frame window — order is unresolvable.
        let seq = KinematicSequence(peaks: peaks(pelvisTime: 2.000, torsoTime: 2.008))
        XCTAssertTrue(seq.isDegenerate)
        XCTAssertFalse(SequencePresentation.isTrustworthy(seq))
    }

    func testNotTrustworthyWhenPeakCountIsNotFour() {
        let seq = KinematicSequence(peaks: Array(peaks().prefix(3)))
        XCTAssertFalse(SequencePresentation.isTrustworthy(seq))
    }

    func testNotTrustworthyWhenPeaksAreEmpty() {
        let seq = KinematicSequence(peaks: [])
        XCTAssertFalse(SequencePresentation.isTrustworthy(seq))
    }
}
