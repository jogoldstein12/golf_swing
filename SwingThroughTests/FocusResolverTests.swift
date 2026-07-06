import XCTest
import SwingKit
@testable import SwingThrough

final class FocusResolverTests: XCTestCase {

    // MARK: - Fixtures (mirrors SwingComparisonTests' builders)

    private func report(
        metrics: [MetricValue],
        score: SwingScore = SwingScore(total: 80, components: [])
    ) -> SwingReport {
        SwingReport(
            club: "7 Iron", view: .downTheLine, duration: 1, frameRate: 30,
            frames: [], checkpoints: [],
            plane: PlaneAnalysis(basePlaneAngle: 55, deviationByPosition: [:], stateByPosition: [:]),
            sequence: KinematicSequence(peaks: []),
            pelvisDOF: [:], chestDOF: [:],
            metrics: metrics, markers: [], score: score, coaching: nil
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

    private func focus(metricLabel: String = "Swing Plane") -> FocusRecord {
        FocusRecord(
            club: "7 Iron", viewRaw: CaptureView.downTheLine.rawValue,
            goalTitle: "Shallow the shaft", metricLabel: metricLabel,
            cue: "Feel the club drop", drillName: "Pump drill"
        )
    }

    // MARK: - Tests

    func testFixedTrendResolves() {
        // out, in, in → last two consecutive MEASURED swings hold in band ⇒ fixed.
        let prior = report(metrics: [metric("Swing Plane", 68, ideal: 52...62)])
        let previous = report(metrics: [metric("Swing Plane", 60, ideal: 52...62)])
        let current = report(metrics: [metric("Swing Plane", 58, ideal: 52...62)])
        let f = focus()
        XCTAssertTrue(FocusResolver.shouldResolve(
            focus: f, history: [prior, previous, current], current: current
        ))
    }

    func testImprovingButNotFixedStaysActive() {
        // out, in → only the newest swing is in band, not yet a held streak.
        let previous = report(metrics: [metric("Swing Plane", 68, ideal: 52...62)])
        let current = report(metrics: [metric("Swing Plane", 60, ideal: 52...62)])
        let f = focus()
        XCTAssertFalse(FocusResolver.shouldResolve(
            focus: f, history: [previous, current], current: current
        ))
    }

    func testWithheldMetricNeverResolves() {
        // Even with an in-band prior, a withheld current measurement can never confirm
        // the streak — the current sample simply doesn't count as measured.
        let previous = report(metrics: [metric("Swing Plane", 58, ideal: 52...62)])
        let current = report(metrics: [
            metric("Swing Plane", 0, ideal: 52...62, provenance: .unavailable,
                   warnings: ["Shaft not detected."])
        ])
        let f = focus()
        XCTAssertFalse(FocusResolver.shouldResolve(
            focus: f, history: [previous, current], current: current
        ))
    }
}
