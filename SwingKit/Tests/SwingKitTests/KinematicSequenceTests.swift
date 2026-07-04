import XCTest
import simd
@testable import SwingKit

final class KinematicSequenceTests: XCTestCase {
    /// Four independently-staggered synthetic angular-velocity bumps (pelvis, chest,
    /// lead arm, club/grip), each a clean sinusoid so its *velocity* peaks exactly at
    /// a chosen time. cameraTransform is held at identity for every frame, so
    /// BodyOrientation's stabilization is a no-op and each segment's raw within-frame
    /// direction IS its recovered turn angle directly — the simplest way to get
    /// precise, independent control per segment for this test (SixDOFTests already
    /// covers the cameraTransform-stabilization math itself against a known rotation).
    private func syntheticSequence() -> ([PoseFrame], SwingTiming) {
        let pelvisT0 = 2.05, chestT0 = 2.15, armT0 = 2.25, clubT0 = 2.35
        let omega = 2 * Double.pi // 1 Hz
        func deg(_ t: Double, amplitude: Double, t0: Double) -> Double { amplitude * sin(omega * (t - t0)) }

        let identityCam: [Double] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, -2, 1]

        var frames: [PoseFrame] = []
        var t = 0.0
        while t <= 3.0 {
            var f = PoseFrame(time: t)
            f.cameraTransform = identityCam

            let thetaP = deg(t, amplitude: 60, t0: pelvisT0) * .pi / 180
            let hipHalf = SIMD3(cos(thetaP), 0, sin(thetaP)) * 0.15
            f.j3[.hipL] = -hipHalf; f.j3[.hipR] = hipHalf
            f.j3[.spine] = SIMD3(0, 0.5, 0.05)

            let thetaC = deg(t, amplitude: 75, t0: chestT0) * .pi / 180
            let shoulderHalf = SIMD3(cos(thetaC), 0, sin(thetaC)) * 0.175
            f.j3[.shoulderL] = -shoulderHalf; f.j3[.shoulderR] = shoulderHalf
            f.j3[.neck] = SIMD3(0, 0.6, 0.05)

            let thetaA = deg(t, amplitude: 50, t0: armT0) * .pi / 180
            f.j3[.wristL] = SIMD3(0.35 * cos(thetaA), -0.1, 0.35 * sin(thetaA))

            let d = 0.6 * sin(omega * (t - clubT0)) / omega
            f.j2[.wristL] = SIMD2(0.5 + d, 0.5)
            f.j2[.wristR] = SIMD2(0.5 + d, 0.5)

            // Body-scale calibration inputs — the club/grip speed series converts
            // image-space to inches via bodyHeight and the head-to-ankle 2D span,
            // and honestly omits the club peak when they're absent.
            f.bodyHeight = 1.8
            f.j2[.head] = SIMD2(0.5, 0.2)
            f.j2[.ankleL] = SIMD2(0.5, 0.8)

            frames.append(f)
            t += 0.04
        }

        let timing = SwingTiming(
            checkpoints: [
                .init(position: .p1, time: 0, frameIndex: 0),
                .init(position: .p4, time: 2.0, frameIndex: Int((2.0 / 0.04).rounded())),
                .init(position: .p7, time: 2.4, frameIndex: Int((2.4 / 0.04).rounded())),
            ],
            handedness: .right, tempoBackswingSeconds: 2.0, tempoDownswingSeconds: 0.4)
        return (frames, timing)
    }

    func testSequenceOrderAndSubFramePeakTimes() {
        let (frames, timing) = syntheticSequence()
        let sequence = KinematicSequenceAnalyzer.analyze(frames: frames, timing: timing)

        XCTAssertEqual(sequence.peaks.count, 4)
        let sorted = sequence.peaks.sorted { $0.time < $1.time }
        XCTAssertEqual(sorted.map(\.segment), [.pelvis, .torso, .leadArm, .club])
        XCTAssertTrue(sequence.isInOrder)

        let expected: [KinematicSequence.Segment: Double] = [
            .pelvis: 2.05, .torso: 2.15, .leadArm: 2.25, .club: 2.35,
        ]
        for peak in sequence.peaks {
            XCTAssertEqual(peak.time, expected[peak.segment]!, accuracy: 0.05,
                          "\(peak.segment) expected ~\(expected[peak.segment]!), got \(peak.time)")
            XCTAssertGreaterThan(peak.peakDegPerSec, 0)
        }
    }
}
