// Picks the concrete PoseFrame to use as the "address reference" for orientation
// stabilization and body-scale calibration.
//
// Why this exists: Vision's 3D request occasionally returns nothing for a frame
// (~4% of frames on the real samples — motion blur, or no clear reason at address),
// and those frames carry no cameraOriginMatrix / bodyHeight. Smoothing gap-fills the
// *joints*, but orientation metadata can't be honestly interpolated. If P1 happens
// to land on such a frame, naively using frames[p1.frameIndex] as the reference
// silently nils out every stabilized quantity downstream (6DOF turn, kinematic
// sequence, 3D plane check) — which is exactly the failure observed in validation.
// The honest fix is cheap: during the address stillness the subject isn't moving, so
// the nearest frame WITH metadata (searched outward from P1, biased earlier-first on
// ties since pre-address frames are guaranteed still) is an equivalent reference.
import Foundation

enum ReferenceFrame {
    /// Nearest frame to `index` carrying full 3D orientation metadata
    /// (cameraTransform), or nil if no frame in the clip has any.
    static func nearestWithOrientation(_ frames: [PoseFrame], to index: Int) -> PoseFrame? {
        nearest(frames, to: index) { $0.cameraTransform?.count == 16 }
    }

    /// Nearest frame to `index` that supports body-scale calibration: bodyHeight
    /// plus the 2D head/ankle joints the scale is measured from.
    static func nearestWithBodyScale(_ frames: [PoseFrame], to index: Int) -> PoseFrame? {
        nearest(frames, to: index) { f in
            (f.bodyHeight ?? 0) > 0
                && (f.j2[.topHead] ?? f.j2[.head]) != nil
                && (f.j2[.ankleL] ?? f.j2[.ankleR]) != nil
        }
    }

    private static func nearest(_ frames: [PoseFrame], to index: Int,
                                where predicate: (PoseFrame) -> Bool) -> PoseFrame? {
        guard !frames.isEmpty else { return nil }
        let clamped = max(0, min(frames.count - 1, index))
        if predicate(frames[clamped]) { return frames[clamped] }
        for offset in 1..<frames.count {
            let before = clamped - offset
            if before >= 0, predicate(frames[before]) { return frames[before] }
            let after = clamped + offset
            if after < frames.count, predicate(frames[after]) { return frames[after] }
        }
        return nil
    }
}
