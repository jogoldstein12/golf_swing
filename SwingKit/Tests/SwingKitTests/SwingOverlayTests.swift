// WS-E — the on-frame overlay resolver's honesty gate, tested headless. The canvas may
// only draw what the pipeline still trusts: a withheld metric yields no drawing primitive,
// and the target is a corridor (known band) or a ghost of the user's OWN prior clean swing.
import XCTest
@testable import SwingKit

final class SwingOverlayTests: XCTestCase {

    private func report(planeValue: Double, provenance: MeasurementProvenance,
                        basis: PlaneAnalysis.Basis? = .shaftDetected) -> SwingReport {
        let metric = MetricValue(
            label: "Swing Plane", value: planeValue, unit: "°", ideal: -1.5...1.5, display: -12...12,
            quality: MeasurementQuality(confidence: 0.9, coverage: 0.9, provenance: provenance))
        let plane = PlaneAnalysis(
            basePlaneAngle: 55,
            deviationByPosition: [.p5: planeValue],
            stateByPosition: [.p5: planeValue > 0 ? .over : .on],
            basis: basis)
        return SwingReport(
            club: "7 Iron", view: .downTheLine, duration: 1, frameRate: 30,
            frames: [], checkpoints: [], plane: plane, sequence: KinematicSequence(peaks: []),
            pelvisDOF: [:], chestDOF: [:], metrics: [metric], markers: [],
            score: SwingScore(total: 70, components: []))
    }

    private func planeGoal() -> CoachGoal {
        CoachGoal(priority: 1, title: "Shallow the shaft in transition", detail: "",
                  metricLabel: "Swing plane at P5", current: "+15° steep", target: "±1.5°",
                  drill: "Pump drill", drillDetail: "", cue: "Drop the club into the corridor")
    }

    // MARK: - The honesty gate

    func testWithheldMetricYieldsNoOverlayPrimitive() {
        let r = report(planeValue: 0, provenance: .unavailable)
        let plan = SwingOverlay.plan(goal: planeGoal(), report: r, prior: nil, skill: .beginner)
        XCTAssertFalse(plan.primitives.contains { $0.isPlaneLine },
                       "a withheld plane metric must not be drawn")
        XCTAssertFalse(plan.primitives.contains { $0.isCorridor })
    }

    func testMeasuredPlaneDrawsLineAndCorridorAtTransition() {
        let r = report(planeValue: 15, provenance: .measured)
        let plan = SwingOverlay.plan(goal: planeGoal(), report: r, prior: nil, skill: .beginner)
        XCTAssertEqual(plan.position, .p5)
        XCTAssertTrue(plan.primitives.contains { $0.isPlaneLine })
        XCTAssertTrue(plan.primitives.contains { $0.isCorridor })
        XCTAssertEqual(plan.caption, "Drop the club into the corridor")
    }

    // MARK: - Reference selection

    func testCleanPriorSwingSwapsCorridorForGhost() {
        let prior = report(planeValue: 0.5, provenance: .measured)   // clean prior swing
        let curr  = report(planeValue: 15, provenance: .measured)
        let plan = SwingOverlay.plan(goal: planeGoal(), report: curr, prior: prior, skill: .beginner)
        XCTAssertTrue(plan.primitives.contains { $0.isGhost }, "a clean prior swing should ghost")
        XCTAssertFalse(plan.primitives.contains { $0.isCorridor }, "ghost supersedes the corridor")
    }

    func testWithheldPriorDoesNotGhost() {
        let prior = report(planeValue: 0.5, provenance: .unavailable) // prior read distrusted
        let curr  = report(planeValue: 15, provenance: .measured)
        let plan = SwingOverlay.plan(goal: planeGoal(), report: curr, prior: prior, skill: .beginner)
        XCTAssertFalse(plan.primitives.contains { $0.isGhost }, "a distrusted prior is not an honest ghost")
        XCTAssertTrue(plan.primitives.contains { $0.isCorridor })
    }

    // MARK: - Progressive disclosure

    func testAdvancedSkillAddsDepthLines() {
        let r = report(planeValue: 15, provenance: .measured)
        let novice = SwingOverlay.plan(goal: planeGoal(), report: r, prior: nil, skill: .beginner)
        let advanced = SwingOverlay.plan(goal: planeGoal(), report: r, prior: nil, skill: .advanced)
        XCTAssertFalse(novice.primitives.contains(.heldReferenceLine))
        XCTAssertTrue(advanced.primitives.contains(.heldReferenceLine))
        XCTAssertTrue(advanced.primitives.contains(.pathTrace))
    }

    // MARK: - Face-on / no plane basis

    func testNoPlaneBasisDrawsNoPlaneLine() {
        let r = report(planeValue: 15, provenance: .measured, basis: nil)
        let plan = SwingOverlay.plan(goal: planeGoal(), report: r, prior: nil, skill: .beginner)
        XCTAssertFalse(plan.primitives.contains { $0.isPlaneLine })
    }
}
