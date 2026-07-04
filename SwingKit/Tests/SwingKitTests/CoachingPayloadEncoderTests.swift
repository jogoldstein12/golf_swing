// Golden-file test for the Claude payload encoder. No network involved: we build a fixed
// synthetic report + context, encode it, and assert the resulting compact Payload structurally
// equals a hand-built expected value. Any change to the encoder that alters the shape or values
// of what Claude sees will fail this test.
import XCTest
@testable import SwingKit

final class CoachingPayloadEncoderTests: XCTestCase {

    static func goldenReport() -> SwingReport {
        let plane = PlaneAnalysis(
            basePlaneAngle: 61,
            deviationByPosition: [.p4: 4.2, .p7: 0.5],
            stateByPosition: [.p4: .over, .p7: .on],
            basis: .shaftDetected,
            planeShift3D: 3.1)
        let sequence = KinematicSequence(peaks: [
            KinematicSequence.Peak(segment: .pelvis, time: 0.05, peakDegPerSec: 512),
            KinematicSequence.Peak(segment: .torso, time: 0.09, peakDegPerSec: 780),
            KinematicSequence.Peak(segment: .leadArm, time: 0.12, peakDegPerSec: 1450),
            KinematicSequence.Peak(segment: .club, time: 0.15, peakDegPerSec: 2500),
        ])
        let pelvisDOF: [SwingPosition: SixDOF] = [
            .p1: SixDOF(),
            .p7: SixDOF(turn: 40, bend: 2, sideBend: 1, sway: 0.5, lift: 0.2, thrust: 2.0),
        ]
        let chestDOF: [SwingPosition: SixDOF] = [
            .p4: SixDOF(turn: 92, bend: 34, sideBend: 5, sway: 0.3, lift: 0.1, thrust: 0.2),
        ]
        let metrics: [MetricValue] = [
            MetricValue(label: "Tempo", value: 3.1, unit: ":1", ideal: 2.7...3.3, display: 1.5...4.5),
            MetricValue(label: "Shoulder Turn", value: 92, unit: "°", ideal: 85...100, display: 40...120, higherIsBetter: true),
        ]
        return SwingReport(
            club: "Driver", view: .downTheLine, duration: 2.8, frameRate: 120,
            frames: [], checkpoints: [
                CheckpointMark(position: .p1, time: 0.0, frameIndex: 0),
                CheckpointMark(position: .p4, time: 0.7, frameIndex: 84),
                CheckpointMark(position: .p7, time: 1.05, frameIndex: 126),
            ],
            plane: plane, sequence: sequence,
            pelvisDOF: pelvisDOF, chestDOF: chestDOF, metrics: metrics, markers: [],
            score: SwingScore(total: 78, components: [
                SwingScore.Component(label: "Sequence", score: 0.95, weight: 0.3),
                SwingScore.Component(label: "Plane", score: 0.6, weight: 0.3),
            ]),
            handedness: .right)
    }

    static func goldenContext() -> CoachingContext {
        CoachingContext(skillLevel: "intermediate", club: "Driver", recentGoalTitles: ["Shallow the shaft in transition"])
    }

    func testCompactPayloadGoldenStructure() {
        let payload = CoachingPayloadEncoder.encode(report: Self.goldenReport(), context: Self.goldenContext())

        let expected = CoachingPayloadEncoder.Payload(
            view: "downTheLine",
            club: "Driver",
            handedness: "right",
            durationSeconds: 2.8,
            checkpoints: [
                .init(position: "P1", time: 0.0),
                .init(position: "P4", time: 0.7),
                .init(position: "P7", time: 1.05),
            ],
            planeBasis: "shaftDetected",
            basePlaneAngle: 61,
            planeShift3D: 3.1,
            plane: [
                .init(position: "P4", deviationDeg: 4.2, state: "over"),
                .init(position: "P7", deviationDeg: 0.5, state: "on"),
            ],
            sequenceIdealOrder: ["pelvis", "torso", "leadArm", "club"],
            sequenceIsInOrder: true,
            sequencePeaks: [
                .init(segment: "pelvis", time: 0.05, peakDegPerSec: 512),
                .init(segment: "torso", time: 0.09, peakDegPerSec: 780),
                .init(segment: "leadArm", time: 0.12, peakDegPerSec: 1450),
                .init(segment: "club", time: 0.15, peakDegPerSec: 2500),
            ],
            pelvisDOF: [
                .init(position: "P1", dof: .init(SixDOF())),
                .init(position: "P7", dof: .init(SixDOF(turn: 40, bend: 2, sideBend: 1, sway: 0.5, lift: 0.2, thrust: 2.0))),
            ],
            chestDOF: [
                .init(position: "P4", dof: .init(SixDOF(turn: 92, bend: 34, sideBend: 5, sway: 0.3, lift: 0.1, thrust: 0.2))),
            ],
            metrics: [
                .init(label: "Tempo", value: 3.1, unit: ":1", idealLow: 2.7, idealHigh: 3.3, inBand: true),
                .init(label: "Shoulder Turn", value: 92, unit: "°", idealLow: 85, idealHigh: 100, inBand: true),
            ],
            score: .init(total: 78, components: [
                .init(label: "Sequence", score: 0.95, weight: 0.3),
                .init(label: "Plane", score: 0.6, weight: 0.3),
            ]),
            context: .init(skillLevel: "intermediate", club: "Driver", recentGoalTitles: ["Shallow the shaft in transition"]))

        XCTAssertEqual(payload, expected)
    }

    /// Frames are never part of the payload — the model must not see pixels or joint tracks.
    func testFramesAndTracksAreStrippedFromPayload() throws {
        let frame = PoseFrame(time: 0.5, j3: [.pelvis: .init(0, 0.9, 0)], j2: [.pelvis: .init(0.5, 0.5)])
        var report = Self.goldenReport()
        report.frames = [frame, frame, frame]

        let json = try CoachingPayloadEncoder.encodeJSONString(report: report, context: Self.goldenContext())
        XCTAssertFalse(json.contains("j3"))
        XCTAssertFalse(json.contains("j2"))
        XCTAssertFalse(json.contains("frames"))
    }

    /// Encoding is a pure function of (report, context) — same inputs, byte-identical JSON.
    func testEncodingIsDeterministic() throws {
        let report = Self.goldenReport()
        let context = Self.goldenContext()
        let a = try CoachingPayloadEncoder.encodeJSONData(report: report, context: context)
        let b = try CoachingPayloadEncoder.encodeJSONData(report: report, context: context)
        XCTAssertEqual(a, b)
    }
}
