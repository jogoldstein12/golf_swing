import XCTest
@testable import SwingKit

final class ConfidenceScoringTests: XCTestCase {
    func testLowCoverageCannotProduceAuthoritativeScore() {
        let input = makeInput(view: .downTheLine)
        let quality = MetricsBuilder.reportQuality(input)
        let score = MetricsBuilder.score(input, metrics: [], quality: quality)

        XCTAssertEqual(score.availability, .insufficientData)
        XCTAssertFalse(score.isAvailable)
    }

    func testFaceOnScoreDoesNotIncludePlaneComponent() {
        let input = makeInput(view: .faceOn, sequence: .init(peaks: [
            .init(segment: .pelvis, time: 0.1, peakDegPerSec: 1),
            .init(segment: .torso, time: 0.2, peakDegPerSec: 1),
            .init(segment: .leadArm, time: 0.3, peakDegPerSec: 1),
            .init(segment: .club, time: 0.4, peakDegPerSec: 1),
        ]))
        let metrics = [
            MetricValue(label: "Swing Plane", value: 0, unit: "°",
                        ideal: -1...1, display: -10...10),
            MetricValue(label: "Tempo", value: 3, unit: ":1",
                        ideal: 2.7...3.3, display: 1...5),
            MetricValue(label: "Spine Angle", value: 34, unit: "°",
                        ideal: 28...40, display: 10...55),
        ]
        let quality = ReportQuality(
            twoDCoverage: 1, threeDCoverage: 1, checkpointConfidence: 1,
            orientationConfidence: 1, planeBasis: nil
        )
        let score = MetricsBuilder.score(input, metrics: metrics, quality: quality)

        XCTAssertFalse(score.components.contains { $0.label == "Plane" })
    }

    func testLegacyScoreWithoutAvailabilityRemainsVisible() {
        XCTAssertTrue(SwingScore(total: 80, components: []).isAvailable)
    }

    func testGeneratedMetricsAlwaysCarryProvenance() {
        var input = makeInput(view: .faceOn)
        input.timing = SwingTiming(
            checkpoints: [], handedness: .right,
            tempoBackswingSeconds: 1.5, tempoDownswingSeconds: 0.5
        )
        let metrics = MetricsBuilder.metrics(input)

        XCTAssertFalse(metrics.isEmpty)
        XCTAssertTrue(metrics.allSatisfy { $0.quality != nil })
    }

    private func makeInput(
        view: CaptureView,
        sequence: KinematicSequence = .init(peaks: [])
    ) -> MetricsBuilder.Inputs {
        MetricsBuilder.Inputs(
            view: view,
            frames: [],
            timing: SwingTiming(
                checkpoints: [], handedness: .right,
                tempoBackswingSeconds: 0, tempoDownswingSeconds: 0
            ),
            plane: PlaneAnalysis(
                basePlaneAngle: 0, deviationByPosition: [:], stateByPosition: [:]
            ),
            pelvisDOF: [:],
            chestDOF: [:],
            sequence: sequence
        )
    }
}
