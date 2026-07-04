// Shared geometry helpers used across checkpoint detection, plane analysis, 6DOF, and
// kinematic sequence. Small, pure functions only — every one of them is unit-testable
// against synthetic geometry with a known answer.
import Foundation
import simd

enum Geometry {
    /// Interior angle at `elbow` between the shoulder and wrist, degrees, using the
    /// subject-local 3D joints (translation-invariant, so this is safe even though
    /// per-frame model space discards world position).
    static func jointAngleDeg(_ a: SIMD3<Double>, _ vertex: SIMD3<Double>, _ b: SIMD3<Double>) -> Double? {
        let v1 = a - vertex, v2 = b - vertex
        let l1 = length(v1), l2 = length(v2)
        guard l1 > 1e-6, l2 > 1e-6 else { return nil }
        let c = max(-1, min(1, dot(v1, v2) / (l1 * l2)))
        return acos(c) * 180 / .pi
    }

    /// Angle of a 3D vector above/below horizontal (model space is +y up), degrees.
    /// 0° = perfectly horizontal (parallel to the ground) — used for "arm parallel".
    static func inclinationFromHorizontalDeg(_ v: SIMD3<Double>) -> Double? {
        let horiz = sqrt(v.x * v.x + v.z * v.z)
        guard horiz > 1e-6 || abs(v.y) > 1e-6 else { return nil }
        return atan2(v.y, horiz) * 180 / .pi
    }

    /// Signed angle (degrees) of a 2D vector from horizontal, image space (y down).
    /// Positive = climbing toward the top-left/top-right relative to horizontal in
    /// the usual on-screen sense (we flip y since image y grows downward).
    static func angleFromHorizontalDeg(_ v: SIMD2<Double>) -> Double {
        atan2(-v.y, v.x) * 180 / .pi
    }

    /// Euclidean distance, 2D.
    static func dist(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { length(a - b) }

    /// Build an orthonormal frame (right, up, forward) for a body segment from three
    /// non-collinear 3D points: `left`/`right` define the segment's lateral axis,
    /// `spineDir` (a point above/along the segment's own long axis) sets the vertical
    /// reference used to disambiguate forward vs. backward.
    /// - right: unit vector left->right (lateral)
    /// - up: unit vector toward `spineDir` from the left/right midpoint, orthogonalized
    /// - forward: right × up (completes a right-handed frame; points out of the chest/pelvis)
    static func segmentFrame(left: SIMD3<Double>, right: SIMD3<Double>, spineDir: SIMD3<Double>)
        -> (right: SIMD3<Double>, up: SIMD3<Double>, forward: SIMD3<Double>)? {
        let lateral = right - left
        guard length(lateral) > 1e-6 else { return nil }
        let r = normalize(lateral)
        let mid = (left + right) * 0.5
        let toSpine = spineDir - mid
        guard length(toSpine) > 1e-6 else { return nil }
        // Orthogonalize toSpine against r (Gram-Schmidt) so up ⟂ right exactly.
        let upRaw = toSpine - r * dot(toSpine, r)
        guard length(upRaw) > 1e-6 else { return nil }
        let u = normalize(upRaw)
        let f = normalize(cross(r, u))
        return (r, u, f)
    }

    /// Rotation (degrees, signed) about the world-vertical axis (+y) that would carry
    /// `from` (a unit vector, projected to the horizontal plane) onto `to`. Used for
    /// turn (yaw) between a segment's current lateral axis and its address lateral axis.
    static func yawDeltaDeg(from: SIMD3<Double>, to: SIMD3<Double>) -> Double {
        let a = SIMD2(from.x, from.z), b = SIMD2(to.x, to.z)
        let la = length(a), lb = length(b)
        guard la > 1e-6, lb > 1e-6 else { return 0 }
        let cosT = max(-1, min(1, dot(a, b) / (la * lb)))
        let sinT = (a.x * b.y - a.y * b.x) / (la * lb) // 2D cross (z-component)
        return atan2(sinT, cosT) * 180 / .pi
    }

    /// Forward/back tilt (sagittal-plane bend) of `up` relative to the reference
    /// `upRef`, measured as the angle change projected in the plane containing world-Y
    /// and the reference forward axis. Positive = tipping further forward (toward
    /// `forwardRef`).
    static func bendDeltaDeg(up: SIMD3<Double>, upRef: SIMD3<Double>, forwardRef: SIMD3<Double>) -> Double {
        // Decompose each `up` vector's tilt away from world-vertical into components
        // along forwardRef (sagittal) and along rightRef (frontal); bend = sagittal.
        let worldUp = SIMD3<Double>(0, 1, 0)
        let rightRef = normalize(cross(forwardRef, worldUp))
        func sagittalTiltDeg(_ v: SIMD3<Double>) -> Double {
            let vn = normalize(v)
            let f = dot(vn, forwardRef)
            let y = dot(vn, worldUp)
            return atan2(f, y) * 180 / .pi
        }
        return sagittalTiltDeg(up) - sagittalTiltDeg(upRef)
    }

    /// Lateral (frontal-plane) tilt change — same idea as bend but along the right axis.
    static func sideBendDeltaDeg(up: SIMD3<Double>, upRef: SIMD3<Double>, forwardRef: SIMD3<Double>) -> Double {
        let worldUp = SIMD3<Double>(0, 1, 0)
        let rightRef = normalize(cross(forwardRef, worldUp))
        func frontalTiltDeg(_ v: SIMD3<Double>) -> Double {
            let vn = normalize(v)
            let r = dot(vn, rightRef)
            let y = dot(vn, worldUp)
            return atan2(r, y) * 180 / .pi
        }
        return frontalTiltDeg(up) - frontalTiltDeg(upRef)
    }
}
