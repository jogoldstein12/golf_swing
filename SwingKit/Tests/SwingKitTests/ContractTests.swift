import XCTest
@testable import SwingKit

final class ContractTests: XCTestCase {
    func testReportRoundTripsThroughJSON() throws {
        let frame = PoseFrame(
            time: 0.5,
            j3: [.pelvis: .init(0, 0.9, 0), .wristL: .init(-0.1, 0.8, 0.3), .wristR: .init(0.1, 0.8, 0.3)],
            j2: [.pelvis: .init(0.5, 0.55)],
            confidence: [.pelvis: 0.98]
        )
        XCTAssertNotNil(frame.grip3)

        let report = SwingReport(
            club: "7 iron", view: .downTheLine, duration: 3.2, frameRate: 60,
            frames: [frame],
            checkpoints: [.init(position: .p1, time: 0.0, frameIndex: 0)],
            plane: .init(basePlaneAngle: 61, deviationByPosition: [.p5: 4.2], stateByPosition: [.p5: .over]),
            sequence: .init(peaks: [.init(segment: .pelvis, time: 0.02, peakDegPerSec: 512)]),
            pelvisDOF: [.p4: .init(turn: 46)], chestDOF: [.p4: .init(turn: 92)],
            metrics: [.init(label: "Shoulder Turn", value: 92, unit: "°", ideal: 85...100, display: 40...120)],
            markers: [.init(id: "t1", position: .p4, joint: .wristL, kind: .fault,
                            title: "Over the top", detail: "4.2° steep")],
            score: .init(total: 86, components: [.init(label: "Sequence", score: 0.9, weight: 0.3)])
        )
        let data = try JSONEncoder().encode(report)
        let back = try JSONDecoder().decode(SwingReport.self, from: data)
        XCTAssertEqual(back.score.total, 86)
        XCTAssertEqual(back.plane.deviationByPosition[.p5], 4.2)
        XCTAssertEqual(back.frames[0].j3[.pelvis]?.y ?? 0, 0.9, accuracy: 1e-9)
    }

    func testMetricFillAndBand() {
        let m = MetricValue(label: "Tempo", value: 3.1, unit: ":1", ideal: 2.7...3.3, display: 1.5...4.5)
        XCTAssertTrue(m.inBand)
        XCTAssertEqual(m.fill, (3.1 - 1.5) / 3.0, accuracy: 1e-9)
    }

    func testBinaryFrameLookupChoosesNearestTimestamp() {
        let report = SwingReport(
            club: "Test", view: .faceOn, duration: 1, frameRate: 30,
            frames: [.init(time: 0.1), .init(time: 0.4), .init(time: 0.9)],
            checkpoints: [],
            plane: .init(basePlaneAngle: 0, deviationByPosition: [:], stateByPosition: [:]),
            sequence: .init(peaks: []), pelvisDOF: [:], chestDOF: [:],
            metrics: [], markers: [], score: .init(total: 0, components: [])
        )
        XCTAssertEqual(report.frame(at: 0.32)?.time, 0.4)
        XCTAssertEqual(report.frame(at: -1)?.time, 0.1)
        XCTAssertEqual(report.frame(at: 2)?.time, 0.9)
    }
}
