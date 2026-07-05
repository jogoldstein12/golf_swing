import XCTest
import SwingKit
@testable import SwingThrough

final class SwingComparisonTests: XCTestCase {

    // MARK: - Fixtures

    /// A minimal report carrying only the fields the comparison logic reads.
    private func report(
        metrics: [MetricValue],
        score: SwingScore = SwingScore(total: 80, components: []),
        coaching: CoachingPlan? = nil
    ) -> SwingReport {
        SwingReport(
            club: "7 Iron", view: .downTheLine, duration: 1, frameRate: 30,
            frames: [], checkpoints: [],
            plane: PlaneAnalysis(basePlaneAngle: 55, deviationByPosition: [:], stateByPosition: [:]),
            sequence: KinematicSequence(peaks: []),
            pelvisDOF: [:], chestDOF: [:],
            metrics: metrics, markers: [], score: score, coaching: coaching
        )
    }

    private func metric(
        _ label: String, _ value: Double, ideal: ClosedRange<Double>,
        unit: String = "°", higherIsBetter: Bool? = nil,
        provenance: MeasurementProvenance = .measured, warnings: [String] = []
    ) -> MetricValue {
        MetricValue(
            label: label, value: value, unit: unit,
            ideal: ideal, display: (ideal.lowerBound - 20)...(ideal.upperBound + 20),
            higherIsBetter: higherIsBetter,
            quality: MeasurementQuality(confidence: 0.9, coverage: 0.9,
                                        provenance: provenance, warnings: warnings)
        )
    }

    // MARK: - Metric deltas

    func testSignedDeltaBandCenteredImprovesTowardBand() {
        let prev = report(metrics: [metric("Swing Plane", 66, ideal: 52...62)])
        let curr = report(metrics: [metric("Swing Plane", 60, ideal: 52...62)])
        let d = SwingComparison.delta(for: "Swing Plane", current: curr, previous: prev)
        XCTAssertNotNil(d)
        XCTAssertEqual(d?.change, -6, accuracy: 1e-9)
        XCTAssertEqual(d?.improved, true)   // 66 (out, +4 above) → 60 (in band)
        XCTAssertEqual(d?.currentInBand, true)
    }

    func testSignedDeltaBandCenteredRegresses() {
        let prev = report(metrics: [metric("Swing Plane", 60, ideal: 52...62)])
        let curr = report(metrics: [metric("Swing Plane", 68, ideal: 52...62)])
        let d = SwingComparison.delta(for: "Swing Plane", current: curr, previous: prev)
        XCTAssertEqual(d?.improved, false)  // in band → 6° above band
    }

    func testHigherIsBetterDeltaDirection() {
        let prev = report(metrics: [metric("Speed", 90, ideal: 100...120, higherIsBetter: true)])
        let curr = report(metrics: [metric("Speed", 105, ideal: 100...120, higherIsBetter: true)])
        let d = SwingComparison.delta(for: "Speed", current: curr, previous: prev)
        XCTAssertEqual(d?.change, 15, accuracy: 1e-9)
        XCTAssertEqual(d?.improved, true)
    }

    func testNoPriorMetricYieldsNilDelta() {
        let prev = report(metrics: [])   // metric absent last time
        let curr = report(metrics: [metric("Swing Plane", 60, ideal: 52...62)])
        XCTAssertNil(SwingComparison.delta(for: "Swing Plane", current: curr, previous: prev))
    }

    func testWithheldMetricIsNeverDifferenced() {
        // Prior swing withheld this metric — no honest delta can be produced.
        let prev = report(metrics: [
            metric("Swing Plane", 0, ideal: 52...62, provenance: .unavailable,
                   warnings: ["Shaft not detected."])
        ])
        let curr = report(metrics: [metric("Swing Plane", 60, ideal: 52...62)])
        XCTAssertNil(SwingComparison.delta(for: "Swing Plane", current: curr, previous: prev))
        // And symmetrically when the current side is withheld.
        XCTAssertNil(SwingComparison.delta(for: "Swing Plane", current: prev, previous: curr))
        // measuredMetric refuses the withheld one outright.
        XCTAssertNil(SwingComparison.measuredMetric("Swing Plane", in: prev))
    }

    // MARK: - Score delta

    func testScoreDeltaSigned() {
        let prev = report(metrics: [], score: SwingScore(total: 74, components: []))
        let curr = report(metrics: [], score: SwingScore(total: 81, components: []))
        XCTAssertEqual(SwingComparison.scoreDelta(current: curr, previous: prev), 7)
    }

    func testScoreDeltaNilWhenEitherSideUnavailable() {
        let avail = report(metrics: [], score: SwingScore(total: 80, components: []))
        let unavailable = report(metrics: [],
            score: SwingScore(total: 0, components: [], availability: .insufficientData))
        XCTAssertNil(SwingComparison.scoreDelta(current: unavailable, previous: avail))
        XCTAssertNil(SwingComparison.scoreDelta(current: avail, previous: unavailable))
    }

    // MARK: - Fixed / improving detection (N=5, M=2)

    /// Chronological history: oldest first, current last.
    private func history(_ values: [Double], ideal: ClosedRange<Double> = 52...62,
                         provenances: [MeasurementProvenance]? = nil) -> [SwingReport] {
        values.enumerated().map { i, v in
            let prov = provenances?[i] ?? .measured
            return report(metrics: [metric("Swing Plane", v, ideal: ideal, provenance: prov)])
        }
    }

    func testFixedWhenLastTwoMeasuredInBand() {
        // out, out, out, in, in  → the last two consecutive measured swings hold in band.
        let h = history([70, 68, 65, 60, 58])
        XCTAssertEqual(SwingComparison.trend(for: "Swing Plane", history: h), .fixed)
    }

    func testNotFixedWhenOnlyLatestInBand() {
        let h = history([70, 68, 65, 66, 60]) // only newest in band
        XCTAssertEqual(SwingComparison.trend(for: "Swing Plane", history: h), .improving)
    }

    func testWithheldMiddleSwingIsSkippedNotBreakingStreak() {
        // in, [withheld], in  → the two MEASURED samples are both in band ⇒ fixed.
        let h = history([58, 0, 60], provenances: [.measured, .unavailable, .measured])
        XCTAssertEqual(SwingComparison.trend(for: "Swing Plane", history: h), .fixed)
    }

    func testInsufficientWhenFewerThanStreakMeasured() {
        let h = history([60, 0], provenances: [.measured, .unavailable]) // one measured sample
        XCTAssertEqual(SwingComparison.trend(for: "Swing Plane", history: h), .insufficient)
    }

    func testRegressingWhenMovingAwayFromBand() {
        let h = history([60, 63, 66]) // in → progressively further above band
        XCTAssertEqual(SwingComparison.trend(for: "Swing Plane", history: h), .regressing)
    }

    func testWindowIgnoresOlderSwings() {
        // 6 swings; the oldest (in band, in band) is outside the N=5 window and the
        // recent five are out of band ⇒ not fixed.
        let h = history([58, 60, 70, 71, 72, 73])
        XCTAssertNotEqual(SwingComparison.trend(for: "Swing Plane", history: h), .fixed)
    }

    // MARK: - Goal ↔ metric resolution

    func testGoalResolvesToTerselyLabelledMetric() {
        let goal = CoachGoal(
            priority: 1, title: "Shallow the shaft", detail: "",
            metricLabel: "Swing plane at P5", current: "+4°", target: "±1.5°",
            drill: "Pump drill", drillDetail: ""
        )
        let r = report(metrics: [metric("Swing Plane", 60, ideal: 52...62)])
        XCTAssertEqual(SwingComparison.metric(for: goal, in: r)?.label, "Swing Plane")
    }

    func testGoalWithoutMeasuredMetricYieldsInsufficientTrend() {
        let goal = CoachGoal(
            priority: 1, title: "Sequence hips first", detail: "",
            metricLabel: "Kinematic sequence", current: "Arms early", target: "Pelvis-led",
            drill: "Step drill", drillDetail: ""
        )
        let curr = report(metrics: [metric("Swing Plane", 60, ideal: 52...62)])
        XCTAssertEqual(
            SwingComparison.goalTrend(goal, history: [curr], current: curr),
            .insufficient
        )
    }
}
