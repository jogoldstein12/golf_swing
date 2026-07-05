// Measurement layer, stage 3: swing window checkpoints (P1-P10), handedness, and tempo.
//
// Everything here works off the *smoothed* track (Smoothing.swift) and grip kinematics
// only — no ML, no hand-authored per-swing tuning.
//
// Detection strategy (revised after validation against real footage — the original
// "first prominent local max of grip distance" approach mis-fired on a transition
// mis-track dip and put P4 mid-backswing):
//   1. P1 (address) and P10 (finish) anchor on genuine sustained-stillness runs.
//   2. The IMPACT ANCHOR is the global peak of grip 2D speed between them — the
//      downswing into impact is far faster than any other grip motion in image
//      space, making this the single most robust landmark in the whole swing.
//   3. P4 (top) = the point of maximum grip distance from address BEFORE the impact
//      anchor (immune to both mid-backswing tracking dips and the high-hands finish,
//      which sits after the anchor), refined to sub-frame by the radial-velocity
//      zero crossing. A paused top (very common) is handled naturally: the pause IS
//      the distance plateau, and the last +/- crossing around it is the reversal.
//   4. P7 (impact) = the radial-velocity -/+ crossing (grip closest to its address
//      position) nearest the impact anchor, sub-frame interpolated.
//   5. P2/P3/P5/P6/P8/P9 fill in between those hard anchors from grip-height and
//      lead-arm-inclination crossings, and the whole set is clamped monotone.
import Foundation
import simd

/// Output of checkpoint detection: the P-system marks, detected handedness (needed to
/// know which arm is "lead" for P3/P5/P9 and which hip is "trail" for P2/P6/P8), and
/// backswing/downswing timing for the tempo metric.
struct SwingTiming {
    var checkpoints: [CheckpointMark]
    var handedness: Handedness
    var tempoBackswingSeconds: Double
    var tempoDownswingSeconds: Double
}

enum CheckpointDetector {
    struct Options {
        /// Grip speed (normalized image units/sec) below which we call the grip "still".
        var quietSpeedThreshold: Double = 0.12
        /// A stillness run must last this long to count as address/finish, not a
        /// mid-swing pause or a tracking dropout.
        var quietMinDuration: Double = 0.5
        /// The backswing top must carry the grip at least this far (normalized image
        /// units) from its address position, or we declare "no swing found" rather
        /// than fabricate checkpoints from noise.
        var minBackswingProminence: Double = 0.10
        init() {}
    }

    static func detect(frames: [PoseFrame], options: Options = .init()) -> SwingTiming? {
        guard frames.count > 8, let motion = Motion.gripSpeed2D(frames) else { return nil }
        let (times, grip, speed) = motion
        let n = frames.count

        // --- P1 / P10 anchors: genuine sustained stillness at the start and tail. ---
        let stillRuns = Motion.quietRuns(times: times, speed: speed,
                                         threshold: options.quietSpeedThreshold,
                                         minDuration: options.quietMinDuration)
        let p1Index = stillRuns.first?.endIndex ?? 0
        var p10Index = n - 1
        if let last = stillRuns.last, last.startIndex > p1Index + 4 {
            p10Index = last.startIndex
        }
        guard p1Index < grip.count, p10Index > p1Index + 4 else { return nil }
        let addressGrip = grip[p1Index]

        // --- Impact anchor: global peak grip speed in the moving segment. ---
        var impactAnchor = p1Index + 1
        for k in (p1Index + 1)...p10Index where speed[k] > speed[impactAnchor] { impactAnchor = k }

        // --- P4 rough position: max distance from address before the impact anchor. ---
        let dist = grip.map { Geometry.dist($0, addressGrip) }
        guard impactAnchor > p1Index + 2 else { return nil }
        var roughTop = p1Index + 1
        for k in (p1Index + 1)...impactAnchor where dist[k] > dist[roughTop] { roughTop = k }
        guard dist[roughTop] > options.minBackswingProminence else { return nil } // no real swing

        // --- handedness from elbow fold (address -> top). ---
        let handedness = HandednessDetector.detect(frames: frames, addressIndex: p1Index, topIndex: roughTop)
        let leadShoulder: Joint = handedness.leadIsLeft ? .shoulderL : .shoulderR
        let trailHip: Joint = handedness.leadIsLeft ? .hipR : .hipL

        // --- lead-arm "above/below horizontal" signal, every frame — from the 2D
        // track: a 3D-horizontal arm projects to a 2D-horizontal segment under a
        // level (tripod) camera regardless of azimuth, and 2D is far more reliable
        // mid-swing than Vision's 3D arm reconstruction (validated: the 3D arms go
        // near-symmetric-garbage around the top). The hand end is the GRIP (wrist
        // midpoint), not the lead wrist alone: both hands ride the club together so
        // the midpoint is an equivalent proxy for the lead-arm line, and it stays
        // solid when one wrist's confidence collapses for a stretch — validation
        // showed the lead wrist alone gets gap-interpolated through mid-swing,
        // sliding P3/P5 toward the top by ~0.2s. Positive = hands above the lead
        // shoulder in the image. ---
        var incl = [Double](repeating: .nan, count: n)
        for k in 0..<n {
            if let s = frames[k].j2[leadShoulder], let g = frames[k].grip2 {
                incl[k] = s.y - g.y // image y is down: hands above shoulder -> positive
            }
        }

        // --- trail-thigh height proxy: trail hip's address height (subject-local). ---
        let hipHeight = frames[p1Index].j3[trailHip]?.y
        var gripY = [Double](repeating: .nan, count: n)
        for k in 0..<n { gripY[k] = frames[k].grip3?.y ?? .nan }

        func firstCrossing(_ series: [Double], from lo: Int, to hi: Int, rising: Bool, about level: Double = 0) -> Int? {
            guard lo >= 0, hi < series.count, lo < hi else { return nil }
            for k in (lo + 1)...hi {
                let a = series[k - 1], b = series[k]
                guard !a.isNaN, !b.isNaN else { continue }
                let da = a - level, db = b - level
                if rising, da <= 0, db > 0 { return k }
                if !rising, da >= 0, db < 0 { return k }
            }
            return nil
        }

        // --- refine P4: the reversal that STARTS the downswing. Many golfers pause
        // at the top (the real fixture pauses ~0.3s), so "max distance from
        // address" marks the START of the pause, not the moment the club changes
        // direction. Tempo and the downswing definitionally begin at the END of the
        // pause: the LAST frame at which grip distance still holds >= 95% of its
        // plateau maximum, sub-frame refined by the nearest radial-velocity zero
        // crossing. For a no-pause swing the plateau is a single sample and this
        // reduces to the plain reversal. (Two rejected formulations, for the
        // record: "first prominent local max" fired on a transition mis-track dip,
        // and "last grip-speed local minimum" chased noise wiggles into the
        // downswing — both caught in validation against the real fixture.) ---
        let radialVel = Smoothing.velocity(dist, times: times)
        var strongestDescent = 0.0
        for k in roughTop...impactAnchor where radialVel[k] < strongestDescent { strongestDescent = radialVel[k] }
        var descentStart = impactAnchor
        if strongestDescent < 0 {
            for k in roughTop...impactAnchor where radialVel[k] < 0.35 * strongestDescent {
                descentStart = k
                break
            }
        }
        var p4Index = roughTop
        for k in roughTop...max(roughTop, descentStart - 1) where dist[k] >= 0.95 * dist[roughTop] {
            p4Index = k
        }
        var p4Time = times[p4Index]
        var bestGap = Double.infinity
        for k in max(p1Index + 1, p4Index - 3)..<min(n - 1, p4Index + 4)
        where radialVel[k] >= 0 && radialVel[k + 1] < 0 {
            if let t = Filters.zeroCrossing(t: times, y: radialVel, after: k), abs(t - times[p4Index]) < bestGap {
                bestGap = abs(t - times[p4Index])
                p4Time = t
            }
        }

        // --- P7 impact: the radial -/+ crossing (closest approach to the address
        // grip position) nearest the impact anchor. ---
        var p7Index = impactAnchor
        var p7Time = times[impactAnchor]
        var bestDist = Double.infinity
        let lo7 = max(p4Index + 1, impactAnchor - 10), hi7 = min(n - 2, impactAnchor + 12)
        if lo7 < hi7 {
            for k in lo7..<hi7 where radialVel[k] <= 0 && radialVel[k + 1] > 0 {
                if dist[k] < bestDist {
                    bestDist = dist[k]
                    p7Index = k
                    p7Time = Filters.zeroCrossing(t: times, y: radialVel, after: k) ?? times[k]
                }
            }
        }
        if bestDist.isInfinite { // no crossing (grip never re-approaches): distance minimum
            var minK = lo7
            for k in lo7...max(lo7, hi7) where dist[k] < dist[minK] { minK = k }
            p7Index = minK
            p7Time = times[minK]
        }

        // --- P2 takeaway: grip passes trail-thigh height moving back. ---
        let p2Index = hipHeight.flatMap { firstCrossing(gripY, from: p1Index, to: p4Index, rising: true, about: $0) }
            ?? min(p1Index + max(1, (p4Index - p1Index) / 3), p4Index)

        // --- P3: lead arm parallel to ground, backswing side. ---
        let p3Index = firstCrossing(incl, from: p2Index, to: p4Index, rising: true) ?? p4Index

        // --- P5 transition: lead arm parallel again on the way down. ---
        let p5Index = firstCrossing(incl, from: p4Index, to: p7Index, rising: false)
            ?? min(p4Index + max(1, (p7Index - p4Index) / 3), p7Index)

        // --- P6 delivery: grip back below trail-hip height in the downswing. ---
        let p6Index = hipHeight.flatMap { firstCrossing(gripY, from: p4Index, to: p7Index, rising: false, about: $0) }
            ?? max(p4Index, p7Index - max(1, (p7Index - p4Index) / 3))

        // --- P8: mirror of P6 in follow-through. ---
        let p8Index = hipHeight.flatMap { firstCrossing(gripY, from: p7Index, to: p10Index, rising: true, about: $0) }
            ?? min(p7Index + 1, p10Index)

        // --- P9: mirror of P3 in follow-through. ---
        let p9Index = firstCrossing(incl, from: p8Index, to: p10Index, rising: true) ?? min(p8Index + 1, p10Index)

        // --- assemble, clamped monotone (a noisy secondary detection is never
        // allowed to reorder the hard anchors). ---
        var idxs = [p1Index, p2Index, p3Index, p4Index, p5Index, p6Index, p7Index, p8Index, p9Index, p10Index]
        for i in 1..<idxs.count { idxs[i] = max(idxs[i], idxs[i - 1]) }
        for i in idxs.indices { idxs[i] = max(0, min(n - 1, idxs[i])) }

        // Times: frame times except the sub-frame-interpolated P4/P7, then clamped
        // monotone as well (a sub-frame refinement is allowed to land slightly
        // before its own frame's timestamp, but never before the previous
        // checkpoint).
        var markTimes = idxs.map { times[$0] }
        markTimes[3] = p4Time
        markTimes[6] = p7Time
        for i in 1..<markTimes.count { markTimes[i] = max(markTimes[i], markTimes[i - 1]) }

        let positions: [SwingPosition] = [.p1, .p2, .p3, .p4, .p5, .p6, .p7, .p8, .p9, .p10]
        let checkpoints = (0..<10).map {
            CheckpointMark(position: positions[$0], time: markTimes[$0], frameIndex: idxs[$0])
        }

        // Tempo backswing runs from takeaway START (P1 = last still frame, i.e.
        // motion onset) to the top — matching how 3:1 tour tempo is conventionally
        // measured (first club movement -> top vs top -> impact).
        return SwingTiming(checkpoints: checkpoints, handedness: handedness,
                            tempoBackswingSeconds: markTimes[3] - markTimes[0],
                            tempoDownswingSeconds: markTimes[6] - markTimes[3])
    }
}

/// Determines handedness from the DIRECTION the whole body turns during the
/// backswing, read from the robust integrated matrix yaw (BodyOrientation). A
/// right-handed golfer's backswing yaw delta reads positive in Vision's model space
/// (calibrated against real footage of a verified right-handed golfer — see
/// docs/VALIDATION.md); a left-handed swing mirrors it. This signal is independent
/// of camera placement (it measures body-vs-camera *rotation*, not image-space
/// left/right) and, critically, doesn't rely on Vision's 3D arm geometry at the top
/// — which validation showed is unreliable there (the model returns near-symmetric
/// guessed arms with the grip equidistant from both shoulders, which is why an
/// earlier elbow-fold-only version misdetected). Elbow fold remains as the fallback
/// for clips with no usable orientation metadata.
enum HandednessDetector {
    static func detect(frames: [PoseFrame], addressIndex: Int, topIndex: Int) -> Handedness {
        guard addressIndex >= 0, addressIndex < frames.count,
              topIndex >= 0, topIndex < frames.count else { return .right }

        // Primary: backswing whole-body yaw direction (trust-gated series).
        if let yaw = BodyOrientation.trustedYawSeriesDeg(frames: frames, referenceIndex: addressIndex),
           topIndex < yaw.count, addressIndex < yaw.count {
            let delta = yaw[topIndex] - yaw[addressIndex]
            if abs(delta) > 10 { return delta > 0 ? .right : .left }
        }

        // Fallback: trail-elbow fold (the trail elbow flexes sharply by the top
        // while the lead stays comparatively extended).
        let addr = frames[addressIndex], top = frames[topIndex]
        func angle(_ f: PoseFrame, _ shoulder: Joint, _ elbow: Joint, _ wrist: Joint) -> Double? {
            guard let s = f.j3[shoulder], let e = f.j3[elbow], let w = f.j3[wrist] else { return nil }
            return Geometry.jointAngleDeg(s, e, w)
        }
        guard let lA0 = angle(addr, .shoulderL, .elbowL, .wristL),
              let lA1 = angle(top, .shoulderL, .elbowL, .wristL),
              let rA0 = angle(addr, .shoulderR, .elbowR, .wristR),
              let rA1 = angle(top, .shoulderR, .elbowR, .wristR) else {
            return .right // insufficient joint data to tell; right-handed is the
                          // common case and this is clearly documented as a fallback.
        }
        let leftFold = lA0 - lA1   // positive = left elbow bent more by the top
        let rightFold = rA0 - rA1
        return leftFold > rightFold ? .left : .right
    }
}
