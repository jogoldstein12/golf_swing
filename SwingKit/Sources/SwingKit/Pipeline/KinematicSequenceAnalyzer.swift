// Measurement layer, stage 6: the kinematic sequence. Angular velocity (deg/s) about
// vertical for pelvis, chest, and the lead arm — same stabilize -> unwrap -> Hampel ->
// SG pipeline as 6DOF turn (BodyOrientation.swift / SegmentSeries.swift), differentiated
// via the SG derivative kernel. Grip linear speed stands in for the club (we don't
// track the clubhead) — see the field-unit note below.
import Foundation
import simd

enum KinematicSequenceAnalyzer {
    static func analyze(frames: [PoseFrame], timing: SwingTiming) -> KinematicSequence {
        guard let p1 = timing.checkpoints.first(where: { $0.position == .p1 }),
              let p4 = timing.checkpoints.first(where: { $0.position == .p4 }),
              let p7 = timing.checkpoints.first(where: { $0.position == .p7 }),
              p1.frameIndex < frames.count else {
            return KinematicSequence(peaks: [])
        }
        let times = frames.map(\.time)
        let scaleFrame = ReferenceFrame.nearestWithBodyScale(frames, to: p1.frameIndex)

        let pelvisSeries = SegmentSeries.compute(frames: frames, segment: .pelvis, referenceIndex: p1.frameIndex)?.turnDeg
        let chestSeries = SegmentSeries.compute(frames: frames, segment: .chest, referenceIndex: p1.frameIndex)?.turnDeg
        let leadArmSeries = leadArmTurnSeries(frames: frames, timing: timing, referenceIndex: p1.frameIndex)
        let clubSeries = scaleFrame.flatMap { clubSpeedSeries(frames: frames, addressFrame: $0) }

        let pelvisVel = pelvisSeries.map { Smoothing.velocity($0, times: times) }
        let chestVel = chestSeries.map { Smoothing.velocity($0, times: times) }
        let leadArmVel = leadArmSeries.map { Smoothing.velocity($0, times: times) }
        // Club is already a speed (not an angle to differentiate) — smooth only.
        let clubVel = clubSeries.map { Filters.savitzkyGolay(Filters.hampel($0, halfWindow: 3)) }

        // Downswing search window, with a small margin past impact since release/
        // club deceleration can peak a frame or two either side of P7 at 25fps.
        let lo = max(0, p4.frameIndex)
        let hi = min(frames.count - 1, p7.frameIndex + max(1, (p7.frameIndex - p4.frameIndex) / 4))

        var peaks: [KinematicSequence.Peak] = []
        func addPeak(_ segment: KinematicSequence.Segment, _ series: [Double]?) {
            guard let series, lo < hi, hi < series.count else { return }
            var bestI = lo
            for i in lo...hi where series[i] > series[bestI] { bestI = i }
            let (t, v) = Filters.parabolicPeak(t: times, y: series, at: bestI)
            peaks.append(.init(segment: segment, time: t, peakDegPerSec: v))
        }
        addPeak(.pelvis, pelvisVel)
        addPeak(.torso, chestVel)
        addPeak(.leadArm, leadArmVel)
        // NOTE: "club" is a linear-speed proxy (grip speed, inches/sec, calibrated via
        // bodyHeight) rather than a true angular velocity — we don't track the
        // clubhead, only the hands. It shares the peakDegPerSec field with the other
        // (genuinely angular, deg/s) segments per the existing Report.swift contract;
        // the unit mismatch is called out here and in docs/VALIDATION.md rather than
        // hidden.
        addPeak(.club, clubVel)

        peaks.sort { $0.time < $1.time }

        var series: [KinematicSequence.Segment: [Double]] = [:]
        if let s = pelvisVel { series[.pelvis] = s }
        if let s = chestVel { series[.torso] = s }
        if let s = leadArmVel { series[.leadArm] = s }
        if let s = clubVel { series[.club] = s }

        // Confidence: if the orientation stream was untrusted for a substantial
        // share of the downswing window, the pelvis/torso peak TIMES sit on
        // interpolated data and their order is not a real measurement.
        var lowConfidence = false
        if lo <= hi {
            let trust = BodyOrientation.orientationTrustMask(frames: frames)
            let untrusted = (lo...hi).filter { $0 < trust.count && !trust[$0] }.count
            lowConfidence = Double(untrusted) / Double(hi - lo + 1) > 0.4
        }

        return KinematicSequence(peaks: peaks, times: times, series: series,
                                 lowConfidence: lowConfidence)
    }

    /// Lead-arm yaw decomposed exactly like the body segments (SegmentSeries):
    ///
    ///     armYaw(i) = trustedBodyYaw(i) + armLocalYaw(i)
    ///
    /// where armLocalYaw integrates the arm direction's WITHIN-LOCAL-COORDS
    /// frame-to-frame yaw increments (no matrix involvement at all, so the
    /// transition-zone matrix corruption documented in BodyOrientation.swift cannot
    /// touch it), Hampel-cleaned before integration. Increments are used for the
    /// local part because the arm genuinely sweeps far past ±180° cumulative;
    /// per-frame increments never approach the wrap boundary.
    private static func leadArmTurnSeries(frames: [PoseFrame], timing: SwingTiming, referenceIndex: Int) -> [Double]? {
        let shoulder: Joint = timing.handedness.leadIsLeft ? .shoulderL : .shoulderR
        let wrist: Joint = timing.handedness.leadIsLeft ? .wristL : .wristR
        let n = frames.count
        guard n > 4,
              let bodyYaw = BodyOrientation.trustedYawSeriesDeg(frames: frames, referenceIndex: referenceIndex)
        else { return nil }

        var increments = [Double](repeating: 0, count: n)
        var any = false
        for i in 1..<n {
            guard let sPrev = frames[i - 1].j3[shoulder], let wPrev = frames[i - 1].j3[wrist],
                  let sCur = frames[i].j3[shoulder], let wCur = frames[i].j3[wrist],
                  let delta = BodyOrientation.yawAngleDeg(from: wPrev - sPrev, to: wCur - sCur) else { continue }
            increments[i] = delta
            any = true
        }
        guard any else { return nil }
        let cleaned = Filters.hampel(increments, halfWindow: 3, k: 3.5)
        var local = [Double](repeating: 0, count: n)
        for i in 1..<n { local[i] = local[i - 1] + cleaned[i] }
        var combined = [Double](repeating: 0, count: n)
        for i in 0..<n { combined[i] = bodyYaw[i] + local[i] }
        return Filters.savitzkyGolay(Filters.hampel(combined, halfWindow: 4, k: 3.0))
    }

    /// Grip linear speed (inches/sec), 2D image-space displacement calibrated via
    /// bodyHeight — the same calibration SixDOFAnalyzer uses for sway/lift/thrust, for
    /// the same reason (validated as plausible-magnitude; the 3D route wasn't).
    private static func clubSpeedSeries(frames: [PoseFrame], addressFrame: PoseFrame) -> [Double]? {
        guard let motion = Motion.gripSpeed2D(frames) else { return nil }
        guard let bh = addressFrame.bodyHeight, bh > 0,
              let head = addressFrame.j2[.topHead] ?? addressFrame.j2[.head],
              let ankle = addressFrame.j2[.ankleL] ?? addressFrame.j2[.ankleR] else { return nil }
        let scale = Geometry.dist(head, ankle) / bh // normalized-image-units per meter
        guard scale > 1e-6 else { return nil }
        return motion.speed.map { $0 / scale * 39.3701 }
    }
}
