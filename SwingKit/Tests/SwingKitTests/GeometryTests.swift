import XCTest
import simd
@testable import SwingKit

final class GeometryTests: XCTestCase {
    // MARK: - PCA plane fit (PlaneShift3D's Mat3.planeNormal)

    /// A point set exactly on a known plane -> the recovered normal must match the
    /// known normal (up to sign) within a tight tolerance.
    func testPlaneNormalRecoversKnownPlane() {
        // Plane tilted 30 degrees off horizontal, normal in the XY plane.
        let tiltDeg = 30.0
        let tiltRad = tiltDeg * .pi / 180
        let normal = normalize(SIMD3<Double>(sin(tiltRad), cos(tiltRad), 0))
        // Two in-plane basis vectors orthogonal to `normal`.
        let u = normalize(cross(normal, SIMD3<Double>(0, 0, 1)))
        let v = cross(normal, u)

        // A genuine 2D spread across the plane (a grid — NOT points along a single
        // line: collinear points don't define a plane, and an earlier draft of this
        // test made exactly that mistake).
        var points: [SIMD3<Double>] = []
        for i in 0..<4 {
            for j in 0..<4 {
                points.append(u * (Double(i) * 0.31 - 0.4) + v * (Double(j) * 0.23 - 0.3))
            }
        }
        guard let recovered = Mat3.planeNormal(points) else { return XCTFail("no normal recovered") }
        let agreement = abs(dot(normalize(recovered), normal)) // 1.0 if parallel (either direction)
        XCTAssertEqual(agreement, 1.0, accuracy: 1e-6)
    }

    func testPlaneNormalHorizontalPlane() {
        // A perfectly horizontal plane (y = 0): normal should be world-up (or down).
        var points: [SIMD3<Double>] = []
        for i in 0..<5 {
            for j in 0..<5 { points.append(SIMD3(Double(i) * 0.1, 0, Double(j) * -0.07)) }
        }
        guard let n = Mat3.planeNormal(points) else { return XCTFail("no normal recovered") }
        XCTAssertEqual(abs(n.y), 1.0, accuracy: 1e-6)
        XCTAssertEqual(abs(n.x), 0.0, accuracy: 1e-6)
    }

    // MARK: - BodyOrientation stabilization / yaw recovery

    /// Synthetic PoseFrame with a known cameraOriginMatrix rotation (pure yaw by
    /// `phiDeg`) and constant (address-identical) body-relative joint geometry.
    /// BodyOrientation.stabilize + yawAngleDeg must recover exactly -phiDeg (see
    /// derivation in the doc comment: for R_M(address) = identity and R_M(t) =
    /// Ry(phi), the stabilized hipR-hipL vector yaw-differs from address by -phi).
    private func yawFrame(phiDeg: Double) -> PoseFrame {
        let phi = phiDeg * .pi / 180
        // Column-major 4x4: rotation Ry(phi) in columns 0-2, translation arbitrary.
        let c0: [Double] = [cos(phi), 0, -sin(phi), 0]
        let c1: [Double] = [0, 1, 0, 0]
        let c2: [Double] = [sin(phi), 0, cos(phi), 0]
        let c3: [Double] = [0, 0, -2, 1]
        var f = PoseFrame(time: 0)
        f.j3[.hipL] = SIMD3(-0.15, 0, 0)
        f.j3[.hipR] = SIMD3(0.15, 0, 0)
        f.cameraTransform = c0 + c1 + c2 + c3
        return f
    }

    func testYawRecoveryExactForSyntheticRotation() {
        let address = yawFrame(phiDeg: 0)
        for testAngle in [0.0, 15.0, 30.0, 90.0, -45.0, -120.0] {
            let frame = yawFrame(phiDeg: testAngle)
            let v = frame.j3[.hipR]! - frame.j3[.hipL]!
            guard let stabilized = BodyOrientation.stabilize(v, from: frame, to: address) else {
                return XCTFail("stabilize failed")
            }
            let addrVec = address.j3[.hipR]! - address.j3[.hipL]!
            guard let recovered = BodyOrientation.yawAngleDeg(from: addrVec, to: stabilized) else {
                return XCTFail("yawAngleDeg failed")
            }
            XCTAssertEqual(recovered, -testAngle, accuracy: 0.05,
                          "expected -\(testAngle), got \(recovered)")
        }
    }

    // MARK: - Elbow angle / handedness signature

    func testJointAngleDegRightAngle() {
        let shoulder = SIMD3<Double>(0, 0, 0)
        let elbow = SIMD3<Double>(0, -0.3, 0)
        let wrist = SIMD3<Double>(0.3, -0.3, 0)
        let angle = Geometry.jointAngleDeg(shoulder, elbow, wrist)
        XCTAssertEqual(angle ?? -1, 90, accuracy: 1e-6)
    }

    func testJointAngleDegStraightArm() {
        let shoulder = SIMD3<Double>(0, 0.6, 0)
        let elbow = SIMD3<Double>(0, 0.3, 0)
        let wrist = SIMD3<Double>(0, 0, 0)
        let angle = Geometry.jointAngleDeg(shoulder, elbow, wrist)
        XCTAssertEqual(angle ?? -1, 180, accuracy: 1e-6)
    }

    // MARK: - Segment frame / bend

    func testSegmentFrameOrthonormal() {
        let left = SIMD3<Double>(-0.2, 0, 0.05)
        let right = SIMD3<Double>(0.2, 0, -0.05)
        let spine = SIMD3<Double>(0, 0.5, 0.1)
        guard let f = Geometry.segmentFrame(left: left, right: right, spineDir: spine) else {
            return XCTFail("no frame")
        }
        XCTAssertEqual(length(f.right), 1.0, accuracy: 1e-9)
        XCTAssertEqual(length(f.up), 1.0, accuracy: 1e-9)
        XCTAssertEqual(length(f.forward), 1.0, accuracy: 1e-9)
        XCTAssertEqual(dot(f.right, f.up), 0.0, accuracy: 1e-9)
        XCTAssertEqual(dot(f.right, f.forward), 0.0, accuracy: 1e-9)
        XCTAssertEqual(dot(f.up, f.forward), 0.0, accuracy: 1e-9)
    }

    func testBendDeltaDegDetectsForwardTilt() {
        // Reference "up" is world vertical; tilt 20 degrees toward `forwardRef`.
        let forwardRef = SIMD3<Double>(0, 0, 1)
        let upRef = SIMD3<Double>(0, 1, 0)
        let tiltRad = 20.0 * .pi / 180
        let tiltedUp = SIMD3<Double>(0, cos(tiltRad), sin(tiltRad))
        let bend = Geometry.bendDeltaDeg(up: tiltedUp, upRef: upRef, forwardRef: forwardRef)
        XCTAssertEqual(bend, 20.0, accuracy: 1e-6)
    }
}
