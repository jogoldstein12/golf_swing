// Recovers the subject's body ORIENTATION change across frames from
// `cameraOriginMatrix`, for turn/bend/sideBend (6DOF), the kinematic-sequence
// angular velocities, and handedness detection.
//
// Empirical grounding (full numbers in docs/VALIDATION.md): Vision's 3D body pose
// puts the root at the origin every frame in a coordinate system whose *orientation*
// also tracks the subject — a joint difference like hipR-hipL, read directly in each
// frame's own local coordinates with no stabilization, stays within a ~±15° band all
// the way through a swing in which the golfer visibly turns 90°+. The local axes
// rotate along with the body, so turn cannot be read off raw per-frame joint
// geometry; it must be recovered from `cameraOriginMatrix` (how the physically-static
// camera's pose looks from inside each frame's rotating local space).
//
// HOW it is recovered matters as much as THAT it is recovered. Three formulations
// were validated against real footage and synthetic known rotations before landing
// on `trustedYawSeriesDeg` (see its doc comment for the design):
//  1. absolute stabilization + atan2 + unwrap — accumulated spurious ±360° offsets
//     when matrix glitches hit the unwrap ("shoulder turn ~200°" nonsense);
//  2. integrated per-frame increments with outlier rejection — wrap-free, but the
//     corrupted transition zone (see below) injected unbounded integration drift
//     (finish turn varied −72°…−134° with filter tuning — a giveaway that the
//     number was construction-dependent, not measured);
//  3. absolute wrapped yaw vs the address matrix, trust-gated by increment churn —
//     bounded by construction, drift-free, and corruption is EXCLUDED rather than
//     filtered. This is what ships.
//
// `stabilize` remains for bounded quantities (bend/sideBend tilt vectors, plane-fit
// points) where no unwrapping is involved and a Hampel over the output suffices.
//
// This is all fundamentally different from the *translation* recovery we tried for
// sway/lift/thrust and rejected (see SixDOFAnalyzer.swift): there, the matrix's
// translation column is dominated by the ~2m camera-to-subject distance, so a few
// degrees of rotation noise multiply into multi-meter spurious movement. Here we
// only ever rotate short direction vectors or integrate small relative rotations.
import Foundation
import simd

enum BodyOrientation {
    /// Rotation part of `cameraOriginMatrix`, if present.
    static func rotation(_ frame: PoseFrame) -> Mat3? {
        guard let m = frame.cameraTransform, m.count == 16 else { return nil }
        let c0 = SIMD3(m[0], m[1], m[2])
        let c1 = SIMD3(m[4], m[5], m[6])
        let c2 = SIMD3(m[8], m[9], m[10])
        return Mat3.fromColumns(c0, c1, c2)
    }

    /// Re-expresses direction `v` (given in `from`'s own local coordinates) in
    /// `reference`'s local coordinates, so it becomes directly comparable to a
    /// direction measured in that other frame.
    static func stabilize(_ v: SIMD3<Double>, from: PoseFrame, to reference: PoseFrame) -> SIMD3<Double>? {
        guard let rFrom = rotation(from), let rRef = rotation(reference) else { return nil }
        return Mat3.multiply(rFrom, rRef.transposed).mulVector(v)
    }

    /// Signed yaw angle (degrees) from `a` to `b`, both projected to the horizontal
    /// (x,z) plane (model space is +y up). Wrapped to (-180, 180].
    static func yawAngleDeg(from a: SIMD3<Double>, to b: SIMD3<Double>) -> Double? {
        let pa = SIMD2(a.x, a.z), pb = SIMD2(b.x, b.z)
        let la = length(pa), lb = length(pb)
        guard la > 1e-9, lb > 1e-9 else { return nil }
        let cosT = dot(pa, pb) / (la * lb)
        let sinT = (pa.x * pb.y - pa.y * pb.x) / (la * lb)
        return atan2(sinT, cosT) * 180 / .pi
    }

    /// Yaw (degrees) of the relative rotation from `prev`'s local frame to `cur`'s,
    /// measured by how R_cur · R_prev^T carries a horizontal reference direction.
    static func yawIncrementDeg(from prev: Mat3, to cur: Mat3) -> Double {
        let v = Mat3.multiply(cur, prev.transposed).mulVector(SIMD3<Double>(1, 0, 0))
        return atan2(v.z, v.x) * 180 / .pi
    }

    /// Whole-body yaw relative to the frame at `referenceIndex` (degrees), one value
    /// per frame, with per-frame TRUST GATING and interpolation across untrusted
    /// spans. nil if no trusted reference exists.
    ///
    /// Design, validated on real footage (numbers in docs/VALIDATION.md):
    ///  * ABSOLUTE, not integrated: a golf swing's true whole-body yaw stays well
    ///    inside ±180° of address, so the wrapped two-frame form
    ///    yaw(R_ref → R_i) is directly usable with no unwrap step (the failure mode
    ///    of an earlier formulation) and no integration drift (the failure mode of
    ///    the next one).
    ///  * TRUST GATING: on real DTL footage the matrix goes chaotically wrong for a
    ///    run of frames around the top (±30-160° frame-to-frame jumps with
    ///    alternating sign, biased low — median filtering cannot recover truth from
    ///    it). Corruption is detected by increment CHURN: over a ±3-frame window,
    ///    sum(|increments|) − |sum(increments)|. Real motion has aligned increments
    ///    (churn ≈ 0, even during the fast unwind through impact); the corrupted
    ///    zone alternates wildly (churn ≫). Untrusted samples are dropped and the
    ///    series is linearly interpolated between trusted anchors — declared,
    ///    bounded smoothing rather than silently poisoned numbers. VALIDATION.md
    ///    states the practical consequence (turn at P4 on DTL clips reads as an
    ///    interpolation between the last trusted pre-top and first trusted post-top
    ///    orientation).
    /// Per-frame trust mask for the orientation matrix, from two independent gates
    /// (see `trustedYawSeriesDeg`). Exposed separately so consumers (kinematic
    /// sequence) can report measurement confidence over their own windows.
    ///
    ///  * RATE gate: an increment implying more than `maxRateDegPerFrame` of yaw per
    ///    elapsed frame is physically impossible for a human body at video frame
    ///    rates — both endpoints of such a transition are untrusted. This catches
    ///    consecutive same-sign garbage (e.g. two ~150° jumps observed back-to-back
    ///    at the top of the real fixture) that the churn gate, by design, cannot:
    ///    aligned increments look like real motion to an alignment test.
    ///  * CHURN gate: alignment failure of increments in a ±3 window — catches the
    ///    alternating-sign chaos that stays under the rate cap.
    static func orientationTrustMask(frames: [PoseFrame], churnLimitDeg: Double = 60,
                                     maxRateDegPerFrame: Double = 40) -> [Bool] {
        let n = frames.count
        let rotations = frames.map(rotation)
        var increments = [Double](repeating: 0, count: n)
        var rateOK = [Bool](repeating: true, count: n)
        var prevIdx: Int?
        for i in 0..<n where rotations[i] != nil {
            if let p = prevIdx {
                guard let previous = rotations[p], let current = rotations[i] else { continue }
                increments[i] = yawIncrementDeg(from: previous, to: current)
                if abs(increments[i]) / Double(max(1, i - p)) > maxRateDegPerFrame {
                    rateOK[i] = false
                    rateOK[p] = false
                }
            }
            prevIdx = i
        }
        var trusted = [Bool](repeating: false, count: n)
        for i in 0..<n {
            guard rotations[i] != nil, rateOK[i] else { continue }
            let lo = max(0, i - 3), hi = min(n - 1, i + 3)
            var sumAbs = 0.0, sum = 0.0
            for k in lo...hi { sumAbs += abs(increments[k]); sum += increments[k] }
            trusted[i] = (sumAbs - abs(sum)) < churnLimitDeg
        }
        return trusted
    }

    static func trustedYawSeriesDeg(frames: [PoseFrame], referenceIndex: Int,
                                    churnLimitDeg: Double = 60) -> [Double]? {
        let n = frames.count
        guard n > 4, referenceIndex >= 0, referenceIndex < n else { return nil }
        let rotations = frames.map(rotation)
        let trusted = orientationTrustMask(frames: frames, churnLimitDeg: churnLimitDeg)

        // Reference: nearest trusted frame to the requested index (during address
        // stillness neighbors are equivalent).
        var refIdx: Int?
        for offset in 0..<n {
            let before = referenceIndex - offset, after = referenceIndex + offset
            if before >= 0, trusted[before] { refIdx = before; break }
            if after < n, trusted[after] { refIdx = after; break }
        }
        guard let ref = refIdx, let rRef = rotations[ref] else { return nil }

        var yaw = [Double](repeating: .nan, count: n)
        for i in 0..<n where trusted[i] {
            guard let rotation = rotations[i] else { continue }
            yaw[i] = yawIncrementDeg(from: rRef, to: rotation)
        }
        guard let filled = Filters.fillGaps(yaw) else { return nil }
        return Filters.savitzkyGolay(Filters.hampel(filled, halfWindow: 4, k: 3.0))
    }
}
