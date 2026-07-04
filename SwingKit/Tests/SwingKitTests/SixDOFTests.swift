import XCTest
import simd
@testable import SwingKit

final class SixDOFTests: XCTestCase {
    /// Synthetic pelvis: body-relative joint geometry constant (a rigid pelvis, no
    /// real deformation), but the whole subject yaws by `phiDeg(i)` — encoded the way
    /// Vision would give it to us, via a per-frame cameraOriginMatrix rotation, with
    /// j3 always reported in the subject's own (co-rotating) local frame. This is
    /// exactly the situation BodyOrientation.swift documents empirically; here we
    /// check the recovery math against an exact, known ground truth instead.
    private func makeFrames(phiDeg: (Int) -> Double, count: Int) -> [PoseFrame] {
        (0..<count).map { i in
            let phi = phiDeg(i) * .pi / 180
            let c0: [Double] = [cos(phi), 0, -sin(phi), 0]
            let c1: [Double] = [0, 1, 0, 0]
            let c2: [Double] = [sin(phi), 0, cos(phi), 0]
            let c3: [Double] = [0, 0, -2, 1]
            var f = PoseFrame(time: Double(i) * 0.04)
            f.j3[.hipL] = SIMD3(-0.15, 0, 0)
            f.j3[.hipR] = SIMD3(0.15, 0, 0)
            f.j3[.spine] = SIMD3(0, 0.5, 0)
            f.cameraTransform = c0 + c1 + c2 + c3
            return f
        }
    }

    func testSegmentSeriesRecoversLinearTurn() {
        // Still for 5 frames, then a steady 3°/frame yaw ramp — mirroring the real
        // pipeline, where the analyzed window always contains stillness before P1
        // (the SG smoother's reflected boundary biases the first ~2 samples of a
        // ramp, so a reference at the very first frame of a ramp is unrealistic).
        let frames = makeFrames(phiDeg: { Double(max(0, $0 - 4)) * 3.0 }, count: 25)
        guard let series = SegmentSeries.compute(frames: frames, segment: .pelvis, referenceIndex: 4) else {
            return XCTFail("no series")
        }
        let zero = series.turnDeg[4]
        // Interior samples should match the exact relationship derived in
        // GeometryTests: turn(i) = -phi(i). Tolerance 1.0°: the reference index sits
        // exactly on the still->ramp corner, and an order-2 SG smoother biases a
        // derivative-discontinuity point by ~0.5° (a real address->takeaway
        // transition is smoother than this synthetic corner).
        for i in [9, 14, 19] {
            let expected = -Double(i - 4) * 3.0
            XCTAssertEqual(series.turnDeg[i] - zero, expected, accuracy: 1.0,
                          "frame \(i): expected turn ~\(expected), got \(series.turnDeg[i] - zero)")
        }
        // Non-increasing through the ramp (a steadily-turning body must not produce
        // a reversing signal).
        for i in 6..<22 {
            XCTAssertLessThanOrEqual(series.turnDeg[i], series.turnDeg[i - 1] + 1e-6)
        }
    }

    func testSixDOFZeroAtAddress() {
        // P1 sits a few frames into the series, mirroring the real pipeline (the
        // analyzed window always includes stillness before address, so P1 is never
        // the literal first sample). This matters because the SG smoother's
        // reflected-boundary handling biases the first/last ~2 samples of a ramp —
        // an earlier draft put P1 at index 0 and measured exactly that bias (~1.4°),
        // not a turn error.
        let frames = makeFrames(phiDeg: { Double(max(0, $0 - 4)) * 4.0 }, count: 24)
        let timing = SwingTiming(
            checkpoints: [
                .init(position: .p1, time: frames[4].time, frameIndex: 4),
                .init(position: .p4, time: frames[14].time, frameIndex: 14),
            ],
            handedness: .right, tempoBackswingSeconds: 0.4, tempoDownswingSeconds: 0.13)
        let result = SixDOFAnalyzer.analyze(frames: frames, timing: timing, view: .downTheLine)
        let p1 = result.pelvis[.p1]
        XCTAssertNotNil(p1)
        XCTAssertEqual(p1?.turn ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(p1?.bend ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(p1?.sideBend ?? -1, 0, accuracy: 1e-9)

        // At frame 14, phi = 40deg -> turn vs address should be ~ -40 (same
        // relationship as GeometryTests derives).
        let p4 = result.pelvis[.p4]
        XCTAssertNotNil(p4)
        XCTAssertEqual(p4?.turn ?? 999, -40, accuracy: 1.0)
    }

    func testBendAndSideBendDeltaRecoverKnownTilt() {
        // Chest tilts forward by 15 degrees between two frames sharing the same
        // (identity) orientation -- exercises Geometry directly, since a single-frame
        // tilt doesn't need cross-frame stabilization.
        let tiltRad = 15.0 * .pi / 180
        let upRef = SIMD3<Double>(0, 1, 0)
        let forwardRef = SIMD3<Double>(0, 0, 1)
        let tiltedUp = SIMD3<Double>(0, cos(tiltRad), sin(tiltRad))
        let bend = Geometry.bendDeltaDeg(up: tiltedUp, upRef: upRef, forwardRef: forwardRef)
        let side = Geometry.sideBendDeltaDeg(up: tiltedUp, upRef: upRef, forwardRef: forwardRef)
        XCTAssertEqual(bend, 15.0, accuracy: 1e-6)
        XCTAssertEqual(side, 0.0, accuracy: 1e-6)
    }
}
