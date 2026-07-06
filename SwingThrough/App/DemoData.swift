// Fixture loading. When the measurement pipeline has produced a real report
// (sample_report.json), that is the only source. Until it exists, a clearly-marked
// provisional report carries the UI: REAL tracks + hand-estimated checkpoint times,
// with placeholder metric values from the design prototype. Nothing provisional
// survives once the pipeline lands.
import CoreGraphics
import Foundation
import SwingKit

enum DemoData {
    /// Decoding the fixture (0.5MB of tracks) is not free — cache it so opening the
    /// sample swing never re-parses on the main thread.
    private static let cached: (report: SwingReport, videoURL: URL, videoSize: CGSize)? = compute()

    static func load() -> (report: SwingReport, videoURL: URL, videoSize: CGSize)? { cached }

    private static func compute() -> (report: SwingReport, videoURL: URL, videoSize: CGSize)? {
        guard let videoURL = Bundle.main.url(forResource: "sample_dtl", withExtension: "mp4") else {
            return nil
        }
        let size = CGSize(width: 1440, height: 2560)

        if let reportURL = Bundle.main.url(forResource: "sample_report", withExtension: "json"),
           let data = try? Data(contentsOf: reportURL),
           let report = try? JSONDecoder().decode(SwingReport.self, from: data) {
            return (report, videoURL, size)
        }
        return (provisional(), videoURL, size)
    }

    // MARK: - Provisional (pre-pipeline) report

    private static func provisional() -> SwingReport {
        let frames: [PoseFrame]
        if let url = Bundle.main.url(forResource: "sample_dtl_tracks", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([PoseFrame].self, from: data) {
            frames = decoded
        } else {
            frames = []
        }

        // Hand-read from the annotated extraction frames (trimmed-clip timeline).
        let checkpoints: [CheckpointMark] = [
            .init(position: .p1, time: 1.50, frameIndex: 37),
            .init(position: .p2, time: 1.90, frameIndex: 47),
            .init(position: .p3, time: 2.60, frameIndex: 65),
            .init(position: .p4, time: 3.20, frameIndex: 80),
            .init(position: .p5, time: 3.55, frameIndex: 89),
            .init(position: .p6, time: 3.95, frameIndex: 99),
            .init(position: .p7, time: 4.18, frameIndex: 104),
            .init(position: .p8, time: 4.55, frameIndex: 114),
            .init(position: .p9, time: 5.20, frameIndex: 130),
            .init(position: .p10, time: 6.40, frameIndex: 160),
        ]

        // Base plane hand-fit to the visible shaft in the address frame.
        let plane = PlaneAnalysis(
            basePlaneAngle: 56,
            deviationByPosition: [.p5: 4.2, .p6: 1.1, .p7: 0.4],
            stateByPosition: [.p5: .over, .p6: .on, .p7: .on],
            basePlaneLine2D: [SIMD2(0.585, 0.802), SIMD2(0.253, 0.318)],
            basis: .shaftDetected
        )

        let sequence = KinematicSequence(peaks: [
            .init(segment: .pelvis, time: 0.10, peakDegPerSec: 480),
            .init(segment: .leadArm, time: 0.24, peakDegPerSec: 790),
            .init(segment: .torso, time: 0.26, peakDegPerSec: 640),
            .init(segment: .club, time: 0.38, peakDegPerSec: 2100),
        ])

        let metrics: [MetricValue] = [
            .init(label: "Swing Plane", value: 56, unit: "°", ideal: 52...62, display: 38...78),
            .init(label: "Tempo", value: 3.1, unit: ":1", ideal: 2.7...3.3, display: 1.5...4.5),
            .init(label: "Shoulder Turn", value: 92, unit: "°", ideal: 85...105, display: 40...120),
            .init(label: "Hip Turn", value: 46, unit: "°", ideal: 38...55, display: 20...80),
            .init(label: "Spine Angle", value: 34, unit: "°", ideal: 28...40, display: 10...60),
        ]

        let markers: [SwingMarker] = [
            .init(id: "a1", position: .p1, joint: .spine, kind: .good, title: "Athletic posture",
                  detail: "Spine tilt of 34° from vertical — a neutral, powerful setup. Weight balanced over the arches."),
            .init(id: "a2", position: .p1, joint: .wristR, kind: .good, title: "Neutral hand position",
                  detail: "Hands sit just inside the lead thigh, shaft in line with the lead arm. Good starting point for an on-plane takeaway."),
            .init(id: "t1", position: .p4, joint: .wristR, kind: .fault, title: "Over the top",
                  detail: "At the top the club works above your base plane — shaft ~4.2° steep. From here it will drop out-to-in, the classic cause of pulls and slices."),
            .init(id: "t2", position: .p4, joint: .shoulderR, kind: .good, title: "Full shoulder turn",
                  detail: "92° of shoulder rotation against 46° of hip turn — strong coil and separation. Power is there; it just needs to be delivered on plane."),
            .init(id: "i1", position: .p7, joint: .wristR, kind: .good, title: "Shaft lean",
                  detail: "Hands lead the clubhead into the ball with forward shaft lean — compresses the ball and de-lofts through impact."),
            .init(id: "i2", position: .p7, joint: .hipR, kind: .fault, title: "Early extension",
                  detail: "The pelvis has thrust ~2 in toward the ball, standing you up slightly. This steepens the shaft and forces compensations through impact."),
            .init(id: "f1", position: .p10, joint: .spine, kind: .good, title: "Balanced finish",
                  detail: "Chest faces the target, weight fully onto the lead side, trail foot released. A stable, repeatable finish."),
        ]

        let score = SwingScore(total: 86, components: [
            .init(label: "Sequence", score: 0.88, weight: 0.30),
            .init(label: "Plane", score: 0.78, weight: 0.25),
            .init(label: "Rotation", score: 0.94, weight: 0.20),
            .init(label: "Posture", score: 0.82, weight: 0.15),
            .init(label: "Tempo", score: 0.97, weight: 0.10),
        ])

        let coaching = CoachingPlan(
            verdict: "Compact and powerful — the shaft steepens slightly at the top.",
            goals: [
                .init(priority: 1, title: "Shallow the shaft in transition",
                      detail: "Your one swing-changer. Feel the trail elbow lead down in front of the hip as the pelvis opens — this drops the club under your steep line and delivers it on plane, squaring the face sooner.",
                      metricLabel: "Swing plane at P5", current: "+4.2° steep", target: "±1.5°",
                      drill: "Pump drill", drillDetail: "Pause at the top, drop hands to trail pocket, then fire."),
                .init(priority: 2, title: "Sequence hips before arms",
                      detail: "The downswing should unload from the ground up: pelvis, then torso, then arms, then club. Right now the arms fire a touch early — sequencing them last recovers speed and consistency.",
                      metricLabel: "Kinematic sequence", current: "Arms early", target: "Pelvis-led",
                      drill: "Step-change drill", drillDetail: "Small lead-foot step to start the downswing."),
                .init(priority: 3, title: "Hold your spine angle",
                      detail: "Keep the pelvis back through impact instead of thrusting toward the ball. Maintaining posture keeps the low point consistent and takes the steepness out of the strike.",
                      metricLabel: "Chest thrust at P7", current: "+2.0 in", target: "±0.5 in",
                      drill: "Chair drill", drillDetail: "Brush your seat against a chair back through impact."),
            ],
            source: .rules
        )

        return SwingReport(
            club: "7 Iron", view: .downTheLine, videoFileName: "sample_dtl.mp4",
            duration: 7.5, frameRate: 25,
            frames: frames, checkpoints: checkpoints, plane: plane, sequence: sequence,
            pelvisDOF: [.p4: .init(turn: 46), .p7: .init(thrust: 2.0)],
            chestDOF: [.p4: .init(turn: 92)],
            metrics: metrics, markers: markers, score: score, coaching: coaching
        )
    }
}
