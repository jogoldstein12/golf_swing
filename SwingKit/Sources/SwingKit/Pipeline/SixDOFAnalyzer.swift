// Measurement layer, stage 5: six degrees of freedom for pelvis and chest, vs address.
//
// Turn / bend / sideBend (angular) come from SegmentSeries, which stabilizes each
// frame's body-relative geometry against address using BodyOrientation
// (cameraOriginMatrix-based) — see BodyOrientation.swift for the empirical case that
// this is needed and trustworthy (with a documented caveat: a handful of frames in
// the fastest part of the downswing are noisy; Hampel-filtered like everywhere else).
//
// Sway / lift / thrust (linear) deliberately do NOT use that 3D machinery. We tried
// recovering the subject's absolute translation from cameraOriginMatrix (the
// natural-seeming approach, since j3 is root-centered every frame) and it failed
// hard: the translation column's magnitude is dominated by the ~2m camera-to-subject
// distance, so ordinary per-frame rotation-estimate noise (a few degrees) multiplies
// into multi-meter spurious "pelvis translation" — for reference, a real pelvis sway
// is under 2 inches. Full numbers are in docs/VALIDATION.md. Instead we use 2D
// image-space displacement of the segment center, calibrated to physical units via
// bodyHeight, which gives inch-scale, plausible numbers on the real samples. That
// only observes the axis that isn't foreshortened away in a given camera view:
// down-the-line sees thrust (toward/away the ball is left-right in a DTL frame) and
// lift, but not sway (target-line motion is along the DTL camera's own optical axis);
// face-on sees sway and lift, but not thrust. The axis a view can't see is reported
// as 0 rather than a fabricated 3D number — SwingReport.fused(dtl:faceOn:)
// (Fusion.swift) fills sway in from the face-on pass.
import Foundation
import simd

enum SixDOFAnalyzer {
    struct Result { var pelvis: [SwingPosition: SixDOF]; var chest: [SwingPosition: SixDOF] }

    static func analyze(frames: [PoseFrame], timing: SwingTiming, view: CaptureView) -> Result {
        guard let p1 = timing.checkpoints.first(where: { $0.position == .p1 }),
              p1.frameIndex < frames.count
        else { return Result(pelvis: [:], chest: [:]) }
        // Translation reference is the true P1 frame: smoothed j2 exists on every
        // frame, and sway/lift/thrust are contractually "vs address" exactly.
        let addressFrame = frames[p1.frameIndex]
        let scale = ReferenceFrame.nearestWithBodyScale(frames, to: p1.frameIndex).flatMap(bodyScale)

        func result(for segment: BodySegment) -> [SwingPosition: SixDOF] {
            guard let series = SegmentSeries.compute(frames: frames, segment: segment, referenceIndex: p1.frameIndex)
            else { return [:] }
            let turnZero = series.turnDeg[p1.frameIndex]
            let bendZero = series.bendDeg[p1.frameIndex]
            let sideZero = series.sideBendDeg[p1.frameIndex]

            var out: [SwingPosition: SixDOF] = [:]
            for mark in timing.checkpoints {
                guard mark.frameIndex < frames.count else { continue }
                let idx = mark.frameIndex
                let (sway, lift, thrust) = translation(segment, addressFrame: addressFrame,
                                                        frame: frames[idx], scale: scale, view: view)
                out[mark.position] = SixDOF(turn: series.turnDeg[idx] - turnZero,
                                           bend: series.bendDeg[idx] - bendZero,
                                           sideBend: series.sideBendDeg[idx] - sideZero,
                                           sway: sway, lift: lift, thrust: thrust)
            }
            out[.p1] = SixDOF() // exactly zero by construction
            return out
        }

        return Result(pelvis: result(for: .pelvis), chest: result(for: .chest))
    }

    /// Segment-center 2D displacement from address, in inches, split into the axes a
    /// given view can actually observe (see file doc comment). The axis this view's
    /// camera geometry forshortens away defaults to 0.
    private static func translation(_ segment: BodySegment, addressFrame: PoseFrame, frame: PoseFrame,
                                    scale: Double?, view: CaptureView) -> (Double, Double, Double) {
        guard let scale, scale > 0,
              let c0 = center2D(addressFrame, segment), let cN = center2D(frame, segment) else { return (0, 0, 0) }
        let dxIn = (cN.x - c0.x) / scale * 39.3701
        let dyIn = -(cN.y - c0.y) / scale * 39.3701 // image y is down; up is positive
        switch view {
        case .downTheLine: return (0, dyIn, dxIn)       // thrust visible, sway foreshortened away
        case .faceOn: return (dxIn, dyIn, 0)            // sway visible, thrust foreshortened away
        case .fused: return (0, dyIn, 0)                // never computed directly at this view; Fusion.swift assembles it
        }
    }

    private static func center2D(_ f: PoseFrame, _ s: BodySegment) -> SIMD2<Double>? {
        guard let l = f.j2[s.left], let r = f.j2[s.right] else { return nil }
        return (l + r) * 0.5
    }

    /// Normalized-image-units per meter, from head-to-ankle 2D span vs bodyHeight.
    private static func bodyScale(_ f: PoseFrame) -> Double? {
        guard let bh = f.bodyHeight, bh > 0 else { return nil }
        guard let head = f.j2[.topHead] ?? f.j2[.head], let ankle = f.j2[.ankleL] ?? f.j2[.ankleR] else { return nil }
        let span = Geometry.dist(head, ankle)
        guard span > 1e-4 else { return nil }
        return span / bh
    }
}
