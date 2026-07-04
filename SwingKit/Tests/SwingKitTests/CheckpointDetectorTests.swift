import XCTest
import simd
@testable import SwingKit

final class CheckpointDetectorTests: XCTestCase {
    /// Smoothstep-interpolated scalar keyframe track (C1-continuous, so sub-frame
    /// peak/zero-crossing refinement behaves sensibly, unlike a piecewise-linear "V").
    private func interp(_ t: Double, _ keyframes: [(Double, Double)]) -> Double {
        guard let first = keyframes.first else { return 0 }
        if t <= first.0 { return first.1 }
        for i in 0..<keyframes.count - 1 {
            let (t0, v0) = keyframes[i], (t1, v1) = keyframes[i + 1]
            if t <= t1 {
                let f = (t - t0) / (t1 - t0)
                let s = f * f * (3 - 2 * f)
                return v0 + (v1 - v0) * s
            }
        }
        return keyframes.last!.1
    }

    /// Still (address) -> back (takeaway/backswing) -> reverse (top) -> down
    /// (downswing, fast) -> still (finish). A right-handed synthetic swing: the
    /// right elbow folds toward the top, the left stays straight.
    private func syntheticSwing() -> [PoseFrame] {
        let gripX: [(Double, Double)] = [(0, 0.5), (1.0, 0.5), (2.0, 0.75), (2.35, 0.5), (3.2, 0.2), (4.4, 0.2)]
        let gripY: [(Double, Double)] = [(0, 0.6), (1.0, 0.6), (2.0, 0.15), (2.35, 0.62), (3.2, 0.1), (4.4, 0.1)]
        let grip3Y: [(Double, Double)] = [(0, -0.5), (1.0, -0.5), (2.0, 0.35), (2.35, -0.45), (3.2, 0.3), (4.4, 0.3)]
        let rightFold: [(Double, Double)] = [(0, 0), (1.0, 0), (2.0, 1.0), (2.35, 0), (4.4, 0)]

        let shoulderL = SIMD3<Double>(-0.2, 0.3, 0.1)
        let shoulderR = SIMD3<Double>(0.2, 0.3, 0.1)

        var frames: [PoseFrame] = []
        let dt = 0.04
        var t = 0.0
        while t <= 4.4 {
            var f = PoseFrame(time: t)
            let gx = interp(t, gripX), gy = interp(t, gripY)
            f.j2[.wristL] = SIMD2(gx, gy); f.j2[.wristR] = SIMD2(gx, gy)
            f.confidence[.wristL] = 0.9; f.confidence[.wristR] = 0.9
            // 2D shoulders: the arm-parallel signal (P3/P5/P9) compares wrist vs
            // shoulder image height.
            f.j2[.shoulderL] = SIMD2(0.45, 0.35); f.j2[.shoulderR] = SIMD2(0.55, 0.35)
            f.confidence[.shoulderL] = 0.9; f.confidence[.shoulderR] = 0.9

            let wrist3 = SIMD3<Double>(0, interp(t, grip3Y), 0)
            f.j3[.wristL] = wrist3; f.j3[.wristR] = wrist3
            f.j3[.shoulderL] = shoulderL; f.j3[.shoulderR] = shoulderR
            f.j3[.hipL] = SIMD3(-0.15, 0, 0); f.j3[.hipR] = SIMD3(0.15, 0, 0)

            // Left (lead) arm: elbow at the midpoint -> perfectly straight always.
            f.j3[.elbowL] = (shoulderL + wrist3) * 0.5

            // Right (trail) arm: elbow offset perpendicular to shoulder->wrist by an
            // amount driven by `fold`, chosen so fold=1 -> ~85 deg elbow angle
            // (derivation in the file's design notes / PR description) and fold=0 ->
            // 180 deg (straight), matching a right-handed golfer's trail-arm fold.
            let fold = interp(t, rightFold)
            let s = shoulderR, w = wrist3
            let mid = (s + w) * 0.5
            let L = length(w - s)
            if L > 1e-6 {
                let d = (w - s) / L
                var perp = cross(d, SIMD3<Double>(0, 0, 1))
                if length(perp) < 1e-6 { perp = cross(d, SIMD3<Double>(0, 1, 0)) }
                perp = normalize(perp)
                let h = fold * 0.546 * L
                f.j3[.elbowR] = mid + perp * h
            } else {
                f.j3[.elbowR] = mid
            }
            frames.append(f)
            t += dt
        }
        return frames
    }

    func testDetectsFullCheckpointSequenceInOrder() throws {
        let frames = syntheticSwing()
        guard let timing = CheckpointDetector.detect(frames: frames) else {
            return XCTFail("detector returned nil")
        }
        XCTAssertEqual(timing.checkpoints.count, 10)
        XCTAssertEqual(timing.handedness, .right, "right elbow folds more at the top -> right-handed")

        // Monotonic, non-decreasing through the whole P1...P10 sequence.
        let times = timing.checkpoints.sorted { $0.position.rawValue < $1.position.rawValue }.map(\.time)
        for i in 1..<times.count {
            XCTAssertLessThanOrEqual(times[i - 1], times[i] + 1e-6,
                                     "checkpoint \(i) out of order: \(times)")
        }

        // P1 (address) should land in the initial still period, well before takeaway.
        let p1 = timing.checkpoints.first { $0.position == .p1 }!
        XCTAssertLessThan(p1.time, 1.05)
        XCTAssertGreaterThan(p1.time, 0.3)

        // P4 (top) should land close to the true top at t=2.0.
        let p4 = timing.checkpoints.first { $0.position == .p4 }!
        XCTAssertEqual(p4.time, 2.0, accuracy: 0.15)

        // P7 (impact) should land close to the true return-to-address at t=2.35.
        let p7 = timing.checkpoints.first { $0.position == .p7 }!
        XCTAssertEqual(p7.time, 2.35, accuracy: 0.15)

        // Tempo: fast downswing relative to the backswing (this synthetic swing is
        // deliberately much quicker down than back).
        XCTAssertGreaterThan(timing.tempoBackswingSeconds, timing.tempoDownswingSeconds)
    }

    func testHandednessDetectorDirectly() {
        let frames = syntheticSwing()
        // address ~ t=0.5 (index ~12), top ~ t=2.0 (index 50)
        let addressIdx = 12, topIdx = 50
        let h = HandednessDetector.detect(frames: frames, addressIndex: addressIdx, topIndex: topIdx)
        XCTAssertEqual(h, .right)
    }
}
