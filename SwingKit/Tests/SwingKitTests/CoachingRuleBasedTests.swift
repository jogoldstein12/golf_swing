import XCTest
@testable import SwingKit

final class CoachingRuleBasedTests: XCTestCase {

    // MARK: - Determinism

    func testDeterministic() async throws {
        let report = Fixtures.overTheTopEarlyExtension()
        let coach = RuleBasedCoach()
        let plan1 = try await coach.coach(report, context: .init())
        let plan2 = try await coach.coach(report, context: .init())

        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        XCTAssertEqual(try enc.encode(plan1), try enc.encode(plan2))
    }

    // MARK: - Chain-priority ordering

    func testSequenceBrokenIsGoalOne() async throws {
        let report = Fixtures.sequenceBroken()
        let plan = try await RuleBasedCoach().coach(report, context: .init())

        XCTAssertFalse(plan.goals.isEmpty)
        let first = plan.goals.first { $0.priority == 1 }
        XCTAssertNotNil(first)
        XCTAssertTrue(first!.metricLabel.lowercased().contains("sequence"),
                       "expected the earliest-chain-link fault (sequence) first, got: \(first!.metricLabel)")
        XCTAssertEqual(first!.current, "Arms early")
    }

    func testPlaneIsGoalOneWhenSequenceIsFine() async throws {
        let report = Fixtures.planeSteepSequenceFine()
        let plan = try await RuleBasedCoach().coach(report, context: .init())

        let first = plan.goals.first { $0.priority == 1 }
        XCTAssertNotNil(first)
        XCTAssertTrue(first!.metricLabel.lowercased().contains("plane"),
                       "expected plane to be goal 1 once sequence is clean, got: \(first!.metricLabel)")
        XCTAssertTrue(first!.current.contains("steep"))
    }

    func testAllInBandProducesRefinementGoalsNeverZero() async throws {
        let report = Fixtures.allInBand()
        let plan = try await RuleBasedCoach().coach(report, context: .init())

        XCTAssertGreaterThanOrEqual(plan.goals.count, 2, "must never return fewer than 2 goals")
        XCTAssertLessThanOrEqual(plan.goals.count, 4, "must never return more than 4 goals")
        XCTAssertFalse(plan.verdict.isEmpty)
        // Refinement goals shouldn't claim a fault exists — current value is inside its own target band.
        for goal in plan.goals {
            XCTAssertFalse(goal.title.isEmpty)
            XCTAssertFalse(goal.drill.isEmpty)
        }
    }

    func testGoalsAreCappedAtFourAndPriorityOrdered() async throws {
        let report = Fixtures.everyTierBroken()
        let plan = try await RuleBasedCoach().coach(report, context: .init())

        XCTAssertLessThanOrEqual(plan.goals.count, 4)
        let priorities = plan.goals.map(\.priority)
        XCTAssertEqual(priorities, priorities.sorted(), "priorities must already be in chain order")
        XCTAssertEqual(priorities, Array(1...plan.goals.count))
        // Earliest broken link (sequence) must still be first even with every tier broken.
        XCTAssertTrue(plan.goals[0].metricLabel.lowercased().contains("sequence"))
    }

    func testEarlyExtensionSurfacesAsPelvisThrustFault() async throws {
        let report = Fixtures.overTheTopEarlyExtension()
        let plan = try await RuleBasedCoach().coach(report, context: .init())

        XCTAssertTrue(plan.goals.contains { $0.metricLabel.lowercased().contains("thrust") },
                      "expected an early-extension (pelvis thrust) goal in: \(plan.goals.map(\.metricLabel))")
    }

    func testSource() async throws {
        let report = Fixtures.allInBand()
        let plan = try await RuleBasedCoach().coach(report, context: .init())
        XCTAssertEqual(plan.source, .rules)
    }

    // MARK: - WS-A: no advice on withheld metrics, honest low-confidence lead, external cues

    /// A withheld turn metric must never surface as a coaching goal.
    func testRuleCoachDoesNotCoachOnWithheldMetric() async throws {
        var report = Fixtures.baseReport(sequencePeaks: Fixtures.idealSequence())
        report.metrics.append(MetricValue(
            label: "X-Factor at Transition", value: 0.8, unit: "°", ideal: 30...55, display: 0...80,
            quality: MeasurementQuality(confidence: 0.1, coverage: 0.3, provenance: .unavailable,
                                        warnings: ["Orientation not trusted at the top."])))
        let plan = try await RuleBasedCoach().coach(report, context: .init())
        XCTAssertFalse(plan.goals.contains { $0.metricLabel == "X-Factor at Transition" },
                       "withheld metric leaked into goals: \(plan.goals.map(\.metricLabel))")
    }

    /// On an insufficient-data read, the lead goal is the capture-quality sentinel, not a fault.
    func testInsufficientDataLeadsWithCaptureQuality() async throws {
        var report = Fixtures.planeSteepSequenceFine()   // has a real plane fault…
        report.score = SwingScore(total: 0, components: [], availability: .insufficientData)  // …but the read is low-confidence
        let plan = try await RuleBasedCoach().coach(report, context: .init())
        XCTAssertEqual(plan.goals.first?.metricLabel, "Capture")
        XCTAssertLessThanOrEqual(plan.goals.count, 2, "low-confidence read caps at capture + one tentative goal")
    }

    /// Every fault goal carries a non-empty external-focus cue with no body-part-only phrasing.
    func testFaultGoalsCarryExternalFocusCue() async throws {
        let plan = try await RuleBasedCoach().coach(Fixtures.everyTierBroken(), context: .init())
        for goal in plan.goals {
            let cue = goal.cue ?? ""
            XCTAssertFalse(cue.isEmpty, "goal \(goal.metricLabel) has no cue")
        }
        // The plane goal's cue is the canvas caption — external, effect-focused.
        if let plane = plan.goals.first(where: { $0.metricLabel.lowercased().contains("plane") }) {
            XCTAssertEqual(plane.cue, "Drop the club into the corridor")
        }
    }
}

// MARK: - Synthetic fixtures

enum Fixtures {
    static func baseReport(
        planeP5: Double = 0.5, planeP6: Double = 0.3, planeState: PlaneState = .on,
        sequencePeaks: [KinematicSequence.Peak],
        chestBendP7: Double = 1.0,
        pelvisThrustP7: Double = 0.1,
        pelvisSwayMax: Double = 0.5,
        tempoValue: Double = 3.0,
        shoulderTurn: Double = 92, hipTurn: Double = 46
    ) -> SwingReport {
        let plane = PlaneAnalysis(
            basePlaneAngle: 60,
            deviationByPosition: [.p5: planeP5, .p6: planeP6],
            stateByPosition: [.p5: planeState, .p6: planeState],
            basis: .shaftDetected)
        let sequence = KinematicSequence(peaks: sequencePeaks)
        let pelvisDOF: [SwingPosition: SixDOF] = [
            .p4: SixDOF(turn: hipTurn),
            .p7: SixDOF(sway: pelvisSwayMax, thrust: pelvisThrustP7),
        ]
        let chestDOF: [SwingPosition: SixDOF] = [
            .p4: SixDOF(turn: shoulderTurn),
            .p7: SixDOF(bend: chestBendP7),
        ]
        let metrics: [MetricValue] = [
            MetricValue(label: "Tempo", value: tempoValue, unit: ":1", ideal: 2.7...3.3, display: 1.5...4.5),
            MetricValue(label: "Shoulder Turn", value: shoulderTurn, unit: "°", ideal: 85...100, display: 40...120, higherIsBetter: true),
            MetricValue(label: "Hip Turn", value: hipTurn, unit: "°", ideal: 40...55, display: 20...70, higherIsBetter: true),
        ]
        return SwingReport(
            club: "7 iron", view: .downTheLine, duration: 3.0, frameRate: 60,
            frames: [], checkpoints: [], plane: plane, sequence: sequence,
            pelvisDOF: pelvisDOF, chestDOF: chestDOF, metrics: metrics, markers: [],
            score: SwingScore(total: 80, components: [
                SwingScore.Component(label: "Sequence", score: 0.9, weight: 0.25),
                SwingScore.Component(label: "Plane", score: 0.8, weight: 0.25),
                SwingScore.Component(label: "Posture", score: 0.85, weight: 0.2),
                SwingScore.Component(label: "Tempo", score: 0.9, weight: 0.15),
                SwingScore.Component(label: "Turn", score: 0.9, weight: 0.15),
            ]))
    }

    static func idealSequence() -> [KinematicSequence.Peak] {
        [
            KinematicSequence.Peak(segment: .pelvis, time: 0.05, peakDegPerSec: 500),
            KinematicSequence.Peak(segment: .torso, time: 0.09, peakDegPerSec: 750),
            KinematicSequence.Peak(segment: .leadArm, time: 0.12, peakDegPerSec: 1400),
            KinematicSequence.Peak(segment: .club, time: 0.15, peakDegPerSec: 2400),
        ]
    }

    /// Arms peak before the torso — the classic "casting" fault.
    static func brokenSequence() -> [KinematicSequence.Peak] {
        [
            KinematicSequence.Peak(segment: .pelvis, time: 0.05, peakDegPerSec: 500),
            KinematicSequence.Peak(segment: .leadArm, time: 0.08, peakDegPerSec: 900),
            KinematicSequence.Peak(segment: .torso, time: 0.10, peakDegPerSec: 700),
            KinematicSequence.Peak(segment: .club, time: 0.14, peakDegPerSec: 2200),
        ]
    }

    static func sequenceBroken() -> SwingReport {
        baseReport(sequencePeaks: brokenSequence())
    }

    static func planeSteepSequenceFine() -> SwingReport {
        baseReport(planeP5: 4.2, planeP6: 2.0, planeState: .over, sequencePeaks: idealSequence())
    }

    static func allInBand() -> SwingReport {
        baseReport(sequencePeaks: idealSequence())
    }

    /// The verification fixture from the task brief: over-the-top plane fault + early extension,
    /// everything else clean.
    static func overTheTopEarlyExtension() -> SwingReport {
        baseReport(planeP5: 4.2, planeP6: 1.0, planeState: .over, sequencePeaks: idealSequence(),
                   chestBendP7: 2.0, pelvisThrustP7: 2.0, pelvisSwayMax: 0.5)
    }

    /// Every tier broken at once — used to test the 4-goal cap and priority ordering.
    static func everyTierBroken() -> SwingReport {
        baseReport(planeP5: 5.0, planeP6: 4.0, planeState: .over, sequencePeaks: brokenSequence(),
                   chestBendP7: 8.0, pelvisThrustP7: 2.5, pelvisSwayMax: 3.0,
                   tempoValue: 1.8, shoulderTurn: 70, hipTurn: 30)
    }
}
