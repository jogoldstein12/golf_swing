// Measurement layer, stage 4: the swing plane (down-the-line only — the headline
// measurement the user most wants to see, per SWING_MODEL.md #2).
//
// Base plane: detected directly from address-frame pixels (ShaftDetector), with a
// grip->ball fallback, and "unavailable" (basis nil, deviations empty) if both fail
// their quality gates. We never invent a plane line. Detection is attempted on a few
// frames around P1 (P1 itself, then slightly earlier/later within the address
// stillness) because a single frame can lose the shaft to waggle motion blur — this
// was observed on the real fixture, where P1's exact frame failed the on-line gate
// while the frame two later passed with contrast 6.5x.
//
// Deviation at P5/P6 — where the grip's downswing path sits relative to the base
// plane, as the signed angle at the base line's ground (ball) anchor between the
// base-plane direction and the anchor->grip direction. + = grip above/outside the
// line (over-the-top side), − = below/under (shallow side), ±1.5° neutral.
//
// Why positional-angular rather than the grip's instantaneous VELOCITY direction
// (the first formulation, rejected in validation): hand velocity at P5 points
// steeply downward on every real swing (the hands drop from the top — physics, not
// a fault) and turns sharply target-ward before impact, so velocity-vs-plane reads
// −35°…−120° even on visually on-plane swings and can never live inside a ±1.5°
// band. The angle-at-the-anchor form is the 2D measure that actually corresponds to
// the coaching concept ("club works above/below the base plane", SWING_MODEL.md #2),
// produces shaft-deviation-scale numbers, and is checkable directly on the overlay:
// the deviation is literally the angle between the drawn green line and a ray from
// its ground end to the grip dot at that checkpoint.
import CoreGraphics
import Foundation
import simd

enum SwingPlaneAnalyzer {
    struct Options {
        var neutralBandDeg: Double = 1.5
        /// Time offsets (seconds) around P1 at which shaft detection is attempted;
        /// the success with the best contrast wins.
        var attemptOffsets: [Double] = [0, -0.15, 0.1, -0.3]
        init() {}
    }

    static func analyze(frames: [PoseFrame], timing: SwingTiming, view: CaptureView,
                        videoURL: URL, options: Options = .init()) async -> PlaneAnalysis {
        let unavailable = PlaneAnalysis(basePlaneAngle: 0, deviationByPosition: [:], stateByPosition: [:])
        guard view == .downTheLine else { return unavailable } // faceOn: honestly empty, never neutral-faked

        guard let p1 = timing.checkpoints.first(where: { $0.position == .p1 }),
              p1.frameIndex < frames.count else { return unavailable }

        var line2D: [SIMD2<Double>]?
        var basis: PlaneAnalysis.Basis?

        // --- shaft detection attempts around P1 ---
        var bestShaft: (ground: CGPoint, upper: CGPoint, contrast: Double)?
        var bestSize: (w: Double, h: Double)?
        for offset in options.attemptOffsets {
            let t = max(0, p1.time + offset)
            guard let idx = nearestFrameIndex(frames, to: t) else { continue }
            let frame = frames[idx]
            guard let grip2 = frame.grip2, let groundY = groundY(of: frame) else { continue }
            guard let image = try? await FrameImage.cgImage(from: videoURL, at: t) else { continue }
            if let shaft = ShaftDetector.detectShaft(image: image, grip2: grip2, groundY2: groundY),
               shaft.contrast > (bestShaft?.contrast ?? 0) {
                bestShaft = shaft
                bestSize = (Double(image.width), Double(image.height))
            }
        }
        if let shaft = bestShaft, let size = bestSize {
            line2D = [SIMD2(shaft.ground.x / size.w, shaft.ground.y / size.h),
                      SIMD2(shaft.upper.x / size.w, shaft.upper.y / size.h)]
            basis = .shaftDetected
        }

        // --- fallback: grip -> ball line ---
        if line2D == nil {
            let addressFrame = frames[p1.frameIndex]
            if let grip2 = addressFrame.grip2, let gY = groundY(of: addressFrame),
               let image = try? await FrameImage.cgImage(from: videoURL, at: p1.time) {
                let w = Double(image.width), h = Double(image.height)
                // The ball sits forward of the body: search around the address grip's
                // x pushed further out along the hip-center -> grip direction, at
                // ankle height. (An earlier lead-ankle-centered region was validated
                // wrong on real footage — the ball is nowhere near the feet in a
                // DTL frame.)
                let hipC = hipCenter2D(addressFrame) ?? SIMD2(grip2.x - 0.15, grip2.y)
                let forward = grip2.x - hipC.x // + = ball side of the body in image x
                let ballX = grip2.x + forward * 1.8
                let region = CGRect(x: (ballX - 0.09) * w, y: (gY - 0.05) * h,
                                    width: 0.18 * w, height: 0.10 * h)
                if let ball = ShaftDetector.detectBall(image: image, searchRegion: region) {
                    let ballN = SIMD2(ball.x / w, ball.y / h)
                    let upper = grip2 + (grip2 - ballN) // symmetric extension past the grip
                    line2D = [ballN, upper]
                    basis = .gripBallLine
                }
            }
        }
        guard let line = line2D, let basisUsed = basis else { return unavailable }

        let baseVec = line[1] - line[0] // ground -> upper: "up the plane"
        let baseAngle = Geometry.angleFromHorizontalDeg(baseVec)

        var deviations: [SwingPosition: Double] = [:]
        var states: [SwingPosition: PlaneState] = [:]
        let anchor = line[0] // ground/ball end of the base line
        for pos in [SwingPosition.p5, .p6] {
            guard let mark = timing.checkpoints.first(where: { $0.position == pos }),
                  mark.frameIndex < frames.count,
                  let grip = frames[mark.frameIndex].grip2 else { continue }
            let ray = grip - anchor
            guard length(ray) > 1e-6 else { continue }
            let cross = baseVec.x * ray.y - baseVec.y * ray.x
            let dotp = baseVec.x * ray.x + baseVec.y * ray.y
            // Sign: "+" must mean the grip sits ABOVE the base line in the image
            // (the over-the-top side — the sky side of the shaft line), for either
            // swing direction. In top-left-origin image coords a point above the
            // line contributes cross-product sign −sign(baseVec.x) (derived by
            // perturbing a point on the line by (0,−ε); Δcross = −ε·baseVec.x), so
            // normalize by the line's x-direction. Verified against the annotated
            // frames (VALIDATION.md): a grip dot visually above the green line
            // must read positive.
            let orientationSign: Double = baseVec.x < 0 ? 1 : -1
            let deviation = orientationSign * (atan2(cross, dotp) * 180 / .pi)
            deviations[pos] = deviation
            if abs(deviation) <= options.neutralBandDeg {
                states[pos] = .neutral
            } else {
                states[pos] = deviation > 0 ? .over : .under
            }
        }

        let shift3D = PlaneShift3D.compute(frames: frames, timing: timing)
        return PlaneAnalysis(basePlaneAngle: baseAngle, deviationByPosition: deviations,
                             stateByPosition: states, basePlaneLine2D: line, basis: basisUsed,
                             planeShift3D: shift3D)
    }

    private static func nearestFrameIndex(_ frames: [PoseFrame], to time: Double) -> Int? {
        guard !frames.isEmpty else { return nil }
        var best = 0
        for (i, f) in frames.enumerated() where abs(f.time - time) < abs(frames[best].time - time) { best = i }
        return best
    }

    private static func groundY(of frame: PoseFrame) -> Double? {
        let ankleYs = [frame.j2[.ankleL]?.y, frame.j2[.ankleR]?.y].compactMap { $0 }
        if ankleYs.isEmpty {
            guard let grip = frame.grip2 else { return nil }
            return min(0.97, grip.y + 0.35)
        }
        return ankleYs.reduce(0, +) / Double(ankleYs.count)
    }

    private static func hipCenter2D(_ frame: PoseFrame) -> SIMD2<Double>? {
        guard let l = frame.j2[.hipL], let r = frame.j2[.hipR] else { return frame.j2[.pelvis] }
        return (l + r) * 0.5
    }
}
