import XCTest
@testable import SwingKit

/// A2 — orientation-aware per-metric provenance. When the 3D body-orientation (yaw)
/// stream is weak through the swing, the metrics that depend on it degrade INDIVIDUALLY
/// (turn / X-factor / plane) while the metrics that don't (tempo / posture) stay
/// measured. The whole report is never blanked when only orientation is thin.
final class OrientationProvenanceTests: XCTestCase {
    private let measured = MeasurementQuality(confidence: 0.9, coverage: 0.9, provenance: .measured)

    private func sample() -> [MetricValue] {
        [
            MetricValue(label: "Shoulder Turn", value: 95, unit: "°", ideal: 85...105, display: 0...140, quality: measured),
            MetricValue(label: "X-Factor at Transition", value: 42, unit: "°", ideal: 35...50, display: 0...75, quality: measured),
            MetricValue(label: "Swing Plane", value: 0.5, unit: "°", ideal: -1.5...1.5, display: -12...12, quality: measured),
            MetricValue(label: "Tempo", value: 3.0, unit: ":1", ideal: 2.7...3.3, display: 1.2...4.8, quality: measured),
            MetricValue(label: "Spine Angle", value: 34, unit: "°", ideal: 28...40, display: 10...55, quality: measured),
        ]
    }

    private func provenance(_ metrics: [MetricValue], _ label: String) -> MeasurementProvenance? {
        metrics.first { $0.label == label }?.quality?.provenance
    }

    func testHighOrientationIsNoOp() {
        let out = MetricsBuilder.degradeForOrientation(sample(), orientationConfidence: 0.9)
        XCTAssertTrue(out.allSatisfy { $0.quality?.provenance == .measured })
    }

    func testModerateOrientationDegradesDependentMetricsToInferred() {
        let out = MetricsBuilder.degradeForOrientation(sample(), orientationConfidence: 0.5)
        XCTAssertEqual(provenance(out, "Shoulder Turn"), .inferred)
        XCTAssertEqual(provenance(out, "X-Factor at Transition"), .inferred)
        XCTAssertEqual(provenance(out, "Swing Plane"), .inferred)
        // Independent metrics are untouched.
        XCTAssertEqual(provenance(out, "Tempo"), .measured)
        XCTAssertEqual(provenance(out, "Spine Angle"), .measured)
    }

    func testVeryLowOrientationWithholdsDependentMetrics() {
        let out = MetricsBuilder.degradeForOrientation(sample(), orientationConfidence: 0.2)
        XCTAssertEqual(provenance(out, "Shoulder Turn"), .unavailable)
        XCTAssertEqual(provenance(out, "X-Factor at Transition"), .unavailable)
        XCTAssertEqual(provenance(out, "Swing Plane"), .unavailable)
        XCTAssertEqual(provenance(out, "Tempo"), .measured)
        XCTAssertEqual(provenance(out, "Spine Angle"), .measured)
    }

    func testDegradedMetricsCarrySpecificWarnings() {
        let out = MetricsBuilder.degradeForOrientation(sample(), orientationConfidence: 0.5)
        let turn = out.first { $0.label == "Shoulder Turn" }
        XCTAssertTrue(turn?.quality?.warnings.contains { $0.contains("3D body rotation") } ?? false)
        // Value is never altered by a provenance change.
        XCTAssertEqual(turn?.value, 95)
        // A metric that stayed measured has no new caveat.
        let tempo = out.first { $0.label == "Tempo" }
        XCTAssertEqual(tempo?.quality?.warnings.count, 0)
    }

    func testDependentAndIndependentSetsArePartitioned() {
        // Guard against the two sets drifting out of sync: no metric is both.
        XCTAssertTrue(MetricsBuilder.orientationDependentMetrics.isDisjoint(with: ["Tempo", "Spine Angle", "Pelvis Sway", "Pelvis Thrust at Impact"]))
    }
}
