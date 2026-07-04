// Shared turn/bend/sideBend series computation for a body segment (pelvis or chest),
// used by both SixDOFAnalyzer (checkpoint snapshots) and KinematicSequenceAnalyzer
// (angular velocity, i.e. the derivative of the turn series).
//
// Turn decomposition (validated on real footage — see BodyOrientation.swift and
// docs/VALIDATION.md for the failure modes this replaces):
//
//     turn_segment(i) = integratedMatrixYaw(i) + localYawDelta_segment(i)
//
//  * integratedMatrixYaw — whole-body yaw from robustly-integrated per-frame
//    relative rotations of cameraOriginMatrix (wrap-free by construction).
//  * localYawDelta — the segment's lateral axis direction WITHIN its own frame's
//    coordinates, measured relative to the reference frame's direction with the
//    bounded two-argument signed-angle form. Its true range is small (±40°), so no
//    unwrapping is ever involved. (An earlier atan2-per-frame + unwrap formulation
//    was validated to blow up when the local direction sits near atan2's ±180°
//    boundary — which it does for a typical stance.)
//
// KNOWN LIMITATION (documented, not hidden): Vision's 3D skeleton is nearly rigid in
// yaw — pelvis-vs-chest twist WITHIN a frame measures only ~±10° on real swings
// where true thorax-pelvis separation ("X-factor") reaches 30-50°. Nearly all
// rotation is carried by the shared matrix yaw. Consequently pelvis turn and chest
// turn track each other more closely than reality, chest turn under-reads at the
// top, pelvis turn over-reads, and X-factor under-reads. The numbers are still
// honestly derived from the tracks (and turn magnitude/timing are sound); the
// compression is a sensor limitation stated in VALIDATION.md rather than
// compensated for with invented corrections.
import Foundation
import simd

struct BodySegment {
    var left: Joint, right: Joint, spineRef: Joint
    static let pelvis = BodySegment(left: .hipL, right: .hipR, spineRef: .spine)
    static let chest = BodySegment(left: .shoulderL, right: .shoulderR, spineRef: .neck)
}

enum SegmentSeries {
    struct Series { var turnDeg: [Double]; var bendDeg: [Double]; var sideBendDeg: [Double] }

    static func frame(_ f: PoseFrame, _ s: BodySegment) -> (right: SIMD3<Double>, up: SIMD3<Double>, forward: SIMD3<Double>)? {
        guard let l = f.j3[s.left], let r = f.j3[s.right], let sp = f.j3[s.spineRef] else { return nil }
        return Geometry.segmentFrame(left: l, right: r, spineDir: sp)
    }

    /// Smoothed turn/bend/sideBend across every frame. Zeroed (approximately) at
    /// `referenceIndex`; callers subtract the exact reference sample for hard zeros.
    static func compute(frames: [PoseFrame], segment: BodySegment, referenceIndex: Int) -> Series? {
        let n = frames.count
        guard n > 4, referenceIndex >= 0, referenceIndex < n else { return nil }
        guard let refSeg = frame(frames[referenceIndex], segment) else { return nil }

        // --- turn: trust-gated whole-body matrix yaw + within-frame local delta ---
        guard let matrixYaw = BodyOrientation.trustedYawSeriesDeg(frames: frames, referenceIndex: referenceIndex)
        else { return nil }
        var localRaw = [Double](repeating: .nan, count: n)
        for i in frames.indices {
            guard let seg = frame(frames[i], segment),
                  let delta = BodyOrientation.yawAngleDeg(from: refSeg.right, to: seg.right) else { continue }
            localRaw[i] = delta
        }
        guard let localFilled = Filters.fillGaps(localRaw) else { return nil }
        let local = Filters.savitzkyGolay(Filters.hampel(localFilled, halfWindow: 4, k: 3.0))
        var turn = [Double](repeating: 0, count: n)
        for i in 0..<n { turn[i] = (matrixYaw[i] - matrixYaw[referenceIndex]) + (local[i] - local[referenceIndex]) }

        // --- bend / sideBend: stabilized tilt vectors (bounded — no unwrap issues;
        // Hampel handles the glitch frames). Reference orientation comes from the
        // nearest metadata-carrying frame (ReferenceFrame.swift). ---
        let orientationRef = ReferenceFrame.nearestWithOrientation(frames, to: referenceIndex)
        var bendRaw = [Double](repeating: .nan, count: n)
        var sideRaw = [Double](repeating: .nan, count: n)
        if let refFrame = orientationRef, let refOriented = frame(refFrame, segment) {
            for i in frames.indices {
                guard let seg = frame(frames[i], segment),
                      let upStab = BodyOrientation.stabilize(seg.up, from: frames[i], to: refFrame) else { continue }
                bendRaw[i] = Geometry.bendDeltaDeg(up: upStab, upRef: refOriented.up, forwardRef: refOriented.forward)
                sideRaw[i] = Geometry.sideBendDeltaDeg(up: upStab, upRef: refOriented.up, forwardRef: refOriented.forward)
            }
        }
        let bend = Filters.fillGaps(bendRaw).map { Filters.savitzkyGolay(Filters.hampel($0, halfWindow: 4, k: 3.0)) }
            ?? [Double](repeating: 0, count: n)
        let side = Filters.fillGaps(sideRaw).map { Filters.savitzkyGolay(Filters.hampel($0, halfWindow: 4, k: 3.0)) }
            ?? [Double](repeating: 0, count: n)
        return Series(turnDeg: turn, bendDeg: bend, sideBendDeg: side)
    }
}
