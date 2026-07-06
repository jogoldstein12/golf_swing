// WS-C — the score reflects measurement RELIABILITY, not just importance:
// a degenerate sequence order isn't scored, and orientation is judged at the top
// (P4/P5), not averaged over a whole clip that a clean address/impact would flatter.
import XCTest
@testable import SwingKit

final class ScoreReliabilityTests: XCTestCase {

    private func peaks(pelvis: Double, torso: Double, arm: Double, club: Double) -> KinematicSequence {
        KinematicSequence(peaks: [
            .init(segment: .pelvis, time: pelvis, peakDegPerSec: 500),
            .init(segment: .torso, time: torso, peakDegPerSec: 700),
            .init(segment: .leadArm, time: arm, peakDegPerSec: 1400),
            .init(segment: .club, time: club, peakDegPerSec: 2400),
        ])
    }

    private func input(sequence: KinematicSequence) -> MetricsBuilder.Inputs {
        MetricsBuilder.Inputs(
            view: .downTheLine, frames: [],
            timing: SwingTiming(checkpoints: [], handedness: .right,
                                tempoBackswingSeconds: 0, tempoDownswingSeconds: 0),
            plane: PlaneAnalysis(basePlaneAngle: 0, deviationByPosition: [:], stateByPosition: [:]),
            pelvisDOF: [:], chestDOF: [:], sequence: sequence)
    }

    private func fullQuality() -> ReportQuality {
        ReportQuality(twoDCoverage: 1, threeDCoverage: 1, checkpointConfidence: 1,
                      orientationConfidence: 1, planeBasis: .shaftDetected)
    }

    // MARK: - Sequence degeneracy

    func testCoincidentPeaksDropSequenceFromScore() {
        let degenerate = peaks(pelvis: 1.000, torso: 1.008, arm: 1.10, club: 1.15)
        XCTAssertTrue(MetricsBuilder.isSequenceDegenerate(degenerate))
        let score = MetricsBuilder.score(input(sequence: degenerate), metrics: [], quality: fullQuality())
        XCTAssertFalse(score.components.contains { $0.label == "Sequence" },
                       "a degenerate sequence must not be scored — its weight redistributes")
    }

    func testStaggeredPeaksKeepSequenceInScore() {
        let ordered = peaks(pelvis: 1.00, torso: 1.05, arm: 1.10, club: 1.15)
        XCTAssertFalse(MetricsBuilder.isSequenceDegenerate(ordered))
        let score = MetricsBuilder.score(input(sequence: ordered), metrics: [], quality: fullQuality())
        XCTAssertTrue(score.components.contains { $0.label == "Sequence" })
    }

    // MARK: - Orientation windowing

    /// A clip trusted everywhere EXCEPT the top scores low on the windowed confidence,
    /// even though the whole-clip average would look fine.
    func testOrientationJudgedAtTopNotWholeClip() {
        // 100 frames at 0.02s; P4 (top) at 1.0s. Trusted everywhere except a band at the top.
        let times = (0..<100).map { Double($0) * 0.02 }
        let trust = times.map { abs($0 - 1.0) > 0.15 }   // untrusted only within ±0.15s of the top
        let checkpoints = [CheckpointMark(position: .p4, time: 1.0, frameIndex: 50)]

        let windowed = MetricsBuilder.windowedFraction(trust: trust, times: times, checkpoints: checkpoints)
        let wholeClip = Double(trust.filter { $0 }.count) / Double(trust.count)

        XCTAssertEqual(windowed, 0, accuracy: 1e-9, "the top is entirely untrusted")
        XCTAssertGreaterThan(wholeClip, 0.8, "but the whole-clip average would flatter it")
    }

    func testWindowingFallsBackToWholeClipWithoutTopCheckpoint() {
        let times = (0..<10).map { Double($0) * 0.1 }
        let trust = Array(repeating: true, count: 10)
        // Only a P1 anchor — no P4/P5, so fall back to the whole-clip fraction.
        let windowed = MetricsBuilder.windowedFraction(
            trust: trust, times: times, checkpoints: [.init(position: .p1, time: 0, frameIndex: 0)])
        XCTAssertEqual(windowed, 1.0, accuracy: 1e-9)
    }

    func testEmptyTrustIsZero() {
        XCTAssertEqual(MetricsBuilder.windowedFraction(trust: [], times: [], checkpoints: []), 0)
    }
}
