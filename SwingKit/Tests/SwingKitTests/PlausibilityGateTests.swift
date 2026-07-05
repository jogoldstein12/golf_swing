import XCTest
@testable import SwingKit

/// A1 — deterministic plausibility gating. Anatomically impossible measurements must be
/// withheld (never clamped), and a degenerate 3D-rotation family must collapse
/// orientation confidence so the score gate stops reporting a confident total. The A0
/// reproduction here is the CI-durable form of the spec's `sample_dtl.mp4` regression:
/// it exercises the exact logic that would have caught A0 without depending on a video
/// decoder (which is unavailable on the CLI host — see docs/VALIDATION.md).
final class PlausibilityGateTests: XCTestCase {
    private let measured = MeasurementQuality(confidence: 0.9, coverage: 0.9, provenance: .measured)

    private func metric(_ label: String, _ value: Double, unit: String = "°") -> MetricValue {
        MetricValue(label: label, value: value, unit: unit,
                    ideal: 0...1, display: 0...1, quality: measured)
    }

    private func quality(orientation: Double) -> ReportQuality {
        ReportQuality(twoDCoverage: 0.9, threeDCoverage: 0.8, checkpointConfidence: 0.9,
                      orientationConfidence: orientation, planeBasis: .shaftDetected)
    }

    // MARK: Envelope boundaries

    func testValueInsideEnvelopeStaysMeasured() {
        for (label, env) in PlausibilityGate.envelopes {
            let inside = metric(label, (env.lowerBound + env.upperBound) / 2)
            let result = PlausibilityGate.apply(metrics: [inside], quality: quality(orientation: 0.8))
            XCTAssertEqual(result.metrics.first?.quality?.provenance, .measured,
                           "\(label) midpoint should stay measured")
            XCTAssertEqual(result.metrics.first?.quality?.warnings.count, 0)
        }
    }

    func testBoundaryValuesAreInclusive() {
        for (label, env) in PlausibilityGate.envelopes {
            for edge in [env.lowerBound, env.upperBound] {
                let result = PlausibilityGate.apply(metrics: [metric(label, edge)],
                                                    quality: quality(orientation: 0.8))
                XCTAssertEqual(result.metrics.first?.quality?.provenance, .measured,
                               "\(label) boundary \(edge) should be inside the envelope")
            }
        }
    }

    func testValueOutsideEnvelopeIsWithheldWithWarning() {
        for (label, env) in PlausibilityGate.envelopes {
            let below = metric(label, env.lowerBound - 0.1)
            let result = PlausibilityGate.apply(metrics: [below], quality: quality(orientation: 0.8))
            let gated = result.metrics.first
            XCTAssertEqual(gated?.quality?.provenance, .unavailable,
                           "\(label) below envelope should be withheld")
            XCTAssertFalse(gated?.quality?.warnings.isEmpty ?? true,
                           "\(label) withheld should carry a specific warning")
            // Value is preserved verbatim — a withheld value is never clamped.
            XCTAssertEqual(gated?.value, env.lowerBound - 0.1)
        }
    }

    func testMetricWithoutEnvelopeIsUntouched() {
        let m = metric("Pelvis Thrust at Impact", 999, unit: "in")
        let result = PlausibilityGate.apply(metrics: [m], quality: quality(orientation: 0.8))
        XCTAssertEqual(result.metrics.first?.quality?.provenance, .measured)
    }

    // MARK: Orientation-confidence feedback

    func testImplausibleRotationCollapsesOrientationConfidence() {
        let metrics = [metric("Shoulder Turn", 4.2)]           // implausible (< 20°)
        let result = PlausibilityGate.apply(metrics: metrics, quality: quality(orientation: 0.84))
        XCTAssertLessThanOrEqual(result.quality.orientationConfidence,
                                 PlausibilityGate.implausibleOrientationConfidence)
        XCTAssertTrue(result.quality.warnings.contains { $0.contains("anatomically impossible") })
    }

    func testPlausibleReportLeavesOrientationConfidenceUntouched() {
        let metrics = [metric("Shoulder Turn", 95), metric("Hip Turn", 45)]
        let result = PlausibilityGate.apply(metrics: metrics, quality: quality(orientation: 0.84))
        XCTAssertEqual(result.quality.orientationConfidence, 0.84)
    }

    // MARK: The A0 regression (deterministic reproduction of the bundled-sample failure)

    func testA0DegenerateReportNoLongerScoresConfident() {
        let input = makeInput(view: .downTheLine, sequence: inOrderSequence())
        let metrics = [
            metric("Shoulder Turn", 4.2),                       // A0: impossible
            metric("Hip Turn", 30),
            metric("X-Factor at Transition", 2.6),              // A0: impossible
            MetricValue(label: "Swing Plane", value: 19.9, unit: "°",
                        ideal: -1.5...1.5, display: -12...12, quality: measured),
            MetricValue(label: "Tempo", value: 3.0, unit: ":1",
                        ideal: 2.7...3.3, display: 1.2...4.8, quality: measured),
            MetricValue(label: "Spine Angle", value: 34, unit: "°",
                        ideal: 28...40, display: 10...55, quality: measured),
        ]
        let q = quality(orientation: 0.84)

        // Before the gate the degenerate report looks confident — the A0 bug.
        let before = MetricsBuilder.score(input, metrics: metrics, quality: q)
        XCTAssertEqual(before.availability, .available)

        // After the gate: impossible rotations are withheld, orientation collapses,
        // and the score gate reports insufficient data.
        let gated = PlausibilityGate.apply(metrics: metrics, quality: q)
        XCTAssertEqual(gated.metrics.first { $0.label == "Shoulder Turn" }?.quality?.provenance, .unavailable)
        XCTAssertEqual(gated.metrics.first { $0.label == "X-Factor at Transition" }?.quality?.provenance, .unavailable)
        XCTAssertEqual(gated.metrics.first { $0.label == "Hip Turn" }?.quality?.provenance, .measured)
        XCTAssertEqual(gated.metrics.first { $0.label == "Tempo" }?.quality?.provenance, .measured)

        let after = MetricsBuilder.score(input, metrics: gated.metrics, quality: gated.quality)
        XCTAssertEqual(after.availability, .insufficientData)
        XCTAssertFalse(after.isAvailable)
    }

    func testValidReportStillScoresConfidentThroughTheGate() {
        let input = makeInput(view: .downTheLine, sequence: inOrderSequence())
        let metrics = [
            MetricValue(label: "Shoulder Turn", value: 95, unit: "°",
                        ideal: 85...105, display: 0...140, higherIsBetter: true, quality: measured),
            MetricValue(label: "Hip Turn", value: 45, unit: "°",
                        ideal: 38...55, display: 0...90, higherIsBetter: true, quality: measured),
            MetricValue(label: "Swing Plane", value: 0.5, unit: "°",
                        ideal: -1.5...1.5, display: -12...12, quality: measured),
            MetricValue(label: "Tempo", value: 3.0, unit: ":1",
                        ideal: 2.7...3.3, display: 1.2...4.8, quality: measured),
            MetricValue(label: "Spine Angle", value: 34, unit: "°",
                        ideal: 28...40, display: 10...55, quality: measured),
        ]
        let gated = PlausibilityGate.apply(metrics: metrics, quality: quality(orientation: 0.84))
        XCTAssertTrue(gated.metrics.allSatisfy { $0.quality?.provenance == .measured })
        let score = MetricsBuilder.score(input, metrics: gated.metrics, quality: gated.quality)
        XCTAssertEqual(score.availability, .available)
    }

    // MARK: Helpers

    private func inOrderSequence() -> KinematicSequence {
        KinematicSequence(peaks: [
            .init(segment: .pelvis, time: 0.1, peakDegPerSec: 1),
            .init(segment: .torso, time: 0.2, peakDegPerSec: 1),
            .init(segment: .leadArm, time: 0.3, peakDegPerSec: 1),
            .init(segment: .club, time: 0.4, peakDegPerSec: 1),
        ])
    }

    private func makeInput(view: CaptureView, sequence: KinematicSequence) -> MetricsBuilder.Inputs {
        MetricsBuilder.Inputs(
            view: view, frames: [],
            timing: SwingTiming(checkpoints: [], handedness: .right,
                                tempoBackswingSeconds: 0, tempoDownswingSeconds: 0),
            plane: PlaneAnalysis(basePlaneAngle: 0, deviationByPosition: [:], stateByPosition: [:]),
            pelvisDOF: [:], chestDOF: [:], sequence: sequence
        )
    }
}
