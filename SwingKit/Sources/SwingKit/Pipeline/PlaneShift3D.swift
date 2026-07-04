// 3D cross-check for the swing plane: fit a plane to the backswing grip3 trajectory
// and another to the downswing grip3 trajectory, and report the change in each
// plane's inclination. Reported as `PlaneAnalysis.planeShift3D` — explicitly lower
// trust than the 2D image-space deviation, which is the primary number (see
// docs/VALIDATION.md).
//
// Why this needs "yaw-stabilization" at all: Vision's 3D body pose puts the root
// (pelvis) at the origin every frame (verified: j3[.pelvis] == (0,0,0) in every frame
// of the sample tracks), so a joint's position is only meaningful *within* that
// frame's own local coordinate system. We confirmed empirically (see VALIDATION.md)
// that the coordinate system's *orientation* also changes substantially frame to
// frame (the `cameraOriginMatrix` rotation component swings by tens of degrees over
// the course of a swing) — almost certainly because the local frame tracks the
// subject's own body orientation, not a fixed gravity/world frame. That means you
// cannot simply collect grip3(t) across many frames into one trajectory and fit a
// plane to it; each point is expressed in a *different*, rotated coordinate system.
// We also tried recovering the subject's absolute *translation* from
// cameraOriginMatrix (for 6DOF sway/lift/thrust) and found it unusable — a few
// degrees of per-frame rotation noise, multiplied by the ~2m camera-to-subject
// distance carried in the translation column, blows up into multi-meter spurious
// "translation" for a human pelvis. That failure mode does NOT apply here: we only
// ever rotate short (arm-length-scale) vectors by the *rotation* part of the matrix,
// so the same noise produces centimeter-scale error, not meters. See Sway/Lift/Thrust
// in SixDOFAnalyzer.swift for how sway/lift/thrust are computed instead (2D
// image-space displacement, calibrated by bodyHeight — deliberately NOT this matrix).
import Foundation
import simd

enum PlaneShift3D {
    static func compute(frames: [PoseFrame], timing: SwingTiming) -> Double? {
        guard let p1 = timing.checkpoints.first(where: { $0.position == .p1 }),
              let p4 = timing.checkpoints.first(where: { $0.position == .p4 }),
              let p7 = timing.checkpoints.first(where: { $0.position == .p7 }),
              p1.frameIndex < frames.count, p4.frameIndex < frames.count, p7.frameIndex < frames.count,
              // Nearest-to-P1 frame with orientation metadata (ReferenceFrame.swift).
              let addressFrame = ReferenceFrame.nearestWithOrientation(frames, to: p1.frameIndex)
        else { return nil }

        func stabilizedGrip(_ i: Int) -> SIMD3<Double>? {
            guard i >= 0, i < frames.count, let g = frames[i].grip3 else { return nil }
            return BodyOrientation.stabilize(g, from: frames[i], to: addressFrame)
        }

        let backRange = min(p1.frameIndex, p4.frameIndex)...max(p1.frameIndex, p4.frameIndex)
        let downRange = min(p4.frameIndex, p7.frameIndex)...max(p4.frameIndex, p7.frameIndex)
        let backPts = backRange.compactMap(stabilizedGrip)
        let downPts = downRange.compactMap(stabilizedGrip)
        guard backPts.count >= 4, downPts.count >= 4,
              let nBack = Mat3.planeNormal(backPts), let nDown = Mat3.planeNormal(downPts) else { return nil }

        func inclinationFromHorizontalDeg(_ n: SIMD3<Double>) -> Double {
            let vertical = SIMD3<Double>(0, 1, 0)
            let angleFromVertical = acos(max(-1, min(1, abs(dot(normalize(n), vertical))))) * 180 / .pi
            return 90 - angleFromVertical // plane's own tilt from horizontal
        }
        return inclinationFromHorizontalDeg(nDown) - inclinationFromHorizontalDeg(nBack)
    }
}

/// Minimal hand-rolled 3x3 matrix — deliberately not simd's matrix types, to keep this
/// self-contained and easy to unit-test against known rotations.
struct Mat3 {
    var r0, r1, r2: SIMD3<Double> // row-major

    static func fromColumns(_ c0: SIMD3<Double>, _ c1: SIMD3<Double>, _ c2: SIMD3<Double>) -> Mat3 {
        Mat3(r0: SIMD3(c0.x, c1.x, c2.x), r1: SIMD3(c0.y, c1.y, c2.y), r2: SIMD3(c0.z, c1.z, c2.z))
    }

    var transposed: Mat3 {
        Mat3(r0: SIMD3(r0.x, r1.x, r2.x), r1: SIMD3(r0.y, r1.y, r2.y), r2: SIMD3(r0.z, r1.z, r2.z))
    }

    func mulVector(_ v: SIMD3<Double>) -> SIMD3<Double> { SIMD3(dot(r0, v), dot(r1, v), dot(r2, v)) }

    static func multiply(_ a: Mat3, _ b: Mat3) -> Mat3 {
        let bt = b.transposed // bt.rows == b's columns
        return Mat3(r0: SIMD3(dot(a.r0, bt.r0), dot(a.r0, bt.r1), dot(a.r0, bt.r2)),
                    r1: SIMD3(dot(a.r1, bt.r0), dot(a.r1, bt.r1), dot(a.r1, bt.r2)),
                    r2: SIMD3(dot(a.r2, bt.r0), dot(a.r2, bt.r1), dot(a.r2, bt.r2)))
    }

    static func + (a: Mat3, b: Mat3) -> Mat3 { Mat3(r0: a.r0 + b.r0, r1: a.r1 + b.r1, r2: a.r2 + b.r2) }
    static func - (a: Mat3, b: Mat3) -> Mat3 { Mat3(r0: a.r0 - b.r0, r1: a.r1 - b.r1, r2: a.r2 - b.r2) }
    static func outer(_ v: SIMD3<Double>) -> Mat3 {
        Mat3(r0: SIMD3(v.x * v.x, v.x * v.y, v.x * v.z),
            r1: SIMD3(v.y * v.x, v.y * v.y, v.y * v.z),
            r2: SIMD3(v.z * v.x, v.z * v.y, v.z * v.z))
    }
    static func scale(_ m: Mat3, _ s: Double) -> Mat3 { Mat3(r0: m.r0 * s, r1: m.r1 * s, r2: m.r2 * s) }

    /// Best-fit plane normal through `points` via PCA on the covariance matrix: power
    /// iteration for the dominant (largest-variance) direction, deflate, iterate again
    /// for the second; the normal is their cross product (the least-variance axis).
    static func planeNormal(_ points: [SIMD3<Double>]) -> SIMD3<Double>? {
        guard points.count > 2 else { return nil }
        let n = Double(points.count)
        let mean = points.reduce(SIMD3<Double>(0, 0, 0), +) / n
        var cov = Mat3(r0: SIMD3(0, 0, 0), r1: SIMD3(0, 0, 0), r2: SIMD3(0, 0, 0))
        for p in points { cov = cov + outer(p - mean) }

        func powerIteration(_ m: Mat3, avoid: SIMD3<Double>? = nil) -> (v: SIMD3<Double>, lambda: Double) {
            var v = SIMD3<Double>(0.5, 0.7, 0.3) // arbitrary non-degenerate seed
            var lambda = 0.0
            for _ in 0..<60 {
                var mv = m.mulVector(v)
                if let a = avoid { mv -= a * dot(mv, a) }
                let l = length(mv)
                guard l > 1e-14 else { break }
                v = mv / l
                lambda = dot(m.mulVector(v), v)
            }
            return (v, lambda)
        }
        let (v1, lambda1) = powerIteration(cov)
        guard length(v1) > 1e-9, lambda1 > 1e-12 else { return nil }
        let deflated = cov - scale(outer(v1), lambda1)
        let (v2, lambda2) = powerIteration(deflated, avoid: v1)
        // Collinearity guard: if the second-largest variance is negligible relative
        // to the first, the points lie on (nearly) a line and don't define a plane —
        // fail closed rather than hand back a junk normal.
        guard lambda2 > 1e-3 * lambda1 else { return nil }
        let normal = cross(v1, v2)
        guard length(normal) > 1e-9 else { return nil }
        return normalize(normal)
    }
}
