// Measurement layer, stage 7: metrics (with ideal bands from docs/SWING_MODEL.md),
// SwingScore, and rule-driven SwingMarker text. Every metric/marker here is built from
// a quantity actually computed upstream — if a quantity isn't available (plane
// unavailable, wrong view for a translational DOF, etc.) the metric/marker is simply
// omitted, never filled with a placeholder.
import Foundation
import simd

enum MetricsBuilder {
    struct Inputs {
        var view: CaptureView
        var frames: [PoseFrame]
        var timing: SwingTiming
        var plane: PlaneAnalysis
        var pelvisDOF: [SwingPosition: SixDOF]
        var chestDOF: [SwingPosition: SixDOF]
        var sequence: KinematicSequence
    }

    // MARK: - Metrics

    static func metrics(_ input: Inputs) -> [MetricValue] {
        var out: [MetricValue] = []
        let quality = reportQuality(input)
        let measured = metricQuality(quality)
        let planeQuality = MeasurementQuality(
            confidence: input.plane.basis == nil ? 0 : measured.confidence,
            coverage: input.plane.basis == nil ? 0 : measured.coverage,
            provenance: input.plane.basis == nil ? .unavailable : .measured,
            warnings: input.plane.basis == nil ? ["Swing plane could not be established."] : []
        )

        // Swing Plane deviation at P5 — ideal ±1.5° (neutral band), DTL only.
        if let dev = input.plane.deviationByPosition[.p5] {
            out.append(MetricValue(label: "Swing Plane", value: dev, unit: "°",
                                   ideal: -1.5...1.5, display: -12...12,
                                   quality: planeQuality))
        }

        // Tempo — backswing:downswing ratio, tour benchmark ~3:1 (SWING_MODEL.md #5).
        if input.timing.tempoBackswingSeconds > 0, input.timing.tempoDownswingSeconds > 0 {
            let ratio = input.timing.tempoBackswingSeconds / input.timing.tempoDownswingSeconds
            out.append(MetricValue(label: "Tempo", value: ratio, unit: ":1",
                                   ideal: 2.7...3.3, display: 1.2...4.8,
                                   quality: measured))
        }

        // Shoulder / Hip turn at P4 (top) — magnitudes (sign is rotation direction,
        // not meaningful for the band comparison). OMITTED when the orientation
        // stream is untrusted at P4 (see BodyOrientation.orientationTrustMask):
        // the 6DOF dictionaries then hold interpolated best-estimates for display,
        // but a metric judged against a band must be a real measurement — and the
        // score's turn component correctly falls back to neutral when these are
        // absent. Validation caught exactly this: "Shoulder Turn 2°" from an
        // untrusted-at-top clip is a false fault, not a measurement.
        if input.orientationTrustedAtP4 {
            if let chestTurn = input.chestDOF[.p4]?.turn {
                out.append(MetricValue(label: "Shoulder Turn", value: abs(chestTurn), unit: "°",
                                       ideal: 85...105, display: 0...140, higherIsBetter: true,
                                       quality: measured))
            }
            if let hipTurn = input.pelvisDOF[.p4]?.turn {
                out.append(MetricValue(label: "Hip Turn", value: abs(hipTurn), unit: "°",
                                       ideal: 38...55, display: 0...90, higherIsBetter: true,
                                       quality: measured))
            }
        }

        // Spine angle at address (single-frame, absolute tilt from vertical — the one
        // 6DOF-adjacent number that does NOT need cross-frame stabilization) + how
        // much it changes by impact (bend delta, already relative to address).
        if let spineAtAddress = input.spineAngleAtAddressDeg {
            out.append(MetricValue(label: "Spine Angle", value: spineAtAddress, unit: "°",
                                   ideal: 28...40, display: 10...55, quality: measured))
        }
        if let bendChange = input.chestDOF[.p7]?.bend {
            out.append(MetricValue(label: "Spine Angle Change at Impact", value: bendChange, unit: "°",
                                   ideal: -4...4, display: -15...15, quality: measured))
        }

        // Pelvis sway — only meaningful from a view that can actually see it
        // (face-on, or fused with a face-on pass); see SixDOFAnalyzer's doc comment.
        if input.view == .faceOn || input.view == .fused {
            let sways = input.pelvisDOF.values.map { abs($0.sway) }
            if let peak = sways.max() {
                out.append(MetricValue(label: "Pelvis Sway", value: peak, unit: "in",
                                       ideal: 0...2, display: 0...6, higherIsBetter: false,
                                       quality: measured))
            }
        }
        // Pelvis thrust at impact — only from down-the-line (or fused).
        if input.view == .downTheLine || input.view == .fused, let thrust = input.pelvisDOF[.p7]?.thrust {
            out.append(MetricValue(label: "Pelvis Thrust at Impact", value: abs(thrust), unit: "in",
                                   ideal: 0...1.5, display: 0...5, higherIsBetter: false,
                                   quality: measured))
        }

        // X-factor (shoulder-hip separation) at transition (P5) — the change in
        // (chest turn - pelvis turn) since address. The whole-body matrix yaw
        // cancels in the subtraction, so this is measurable even when absolute turn
        // is untrusted — but it inherits the pose model's yaw-rigidity compression
        // (SegmentSeries.swift doc): expect systematic under-reading vs the 35-50°
        // band. Kept as an honest relative indicator; VALIDATION.md details the
        // bias.
        if let chestP5 = input.chestDOF[.p5]?.turn, let pelvisP5 = input.pelvisDOF[.p5]?.turn {
            out.append(MetricValue(label: "X-Factor at Transition", value: abs(chestP5 - pelvisP5), unit: "°",
                                   ideal: 35...50, display: 0...75, higherIsBetter: true,
                                   quality: measured))
        }
        return degradeForOrientation(out, orientationConfidence: quality.orientationConfidence)
    }

    // MARK: - A2: orientation-aware per-metric provenance

    /// Metrics whose value is derived from the 3D body-orientation (yaw) stream. Turn,
    /// X-factor, and plane deviation lean on it; tempo, posture, and the translational
    /// DOF do not. When the yaw stream is weak through the swing these degrade
    /// INDIVIDUALLY — not the whole report — so an honest read still surfaces the
    /// metrics that don't depend on orientation.
    static let orientationDependentMetrics: Set<String> =
        ["Swing Plane", "Shoulder Turn", "Hip Turn", "X-Factor at Transition"]

    /// Below this fraction of trusted-orientation frames a dependent metric can no
    /// longer be called `.measured` — it becomes an `.inferred` estimate shown with a
    /// caveat. Chosen above the `.score` orientation gate (0.35) so metrics degrade to
    /// "estimate" before the whole report tips to insufficient. Documented in
    /// docs/VALIDATION.md.
    static let orientationInferredThreshold = 0.60
    /// Below this the dependent metric is withheld entirely (`.unavailable`).
    static let orientationWithheldThreshold = 0.35

    /// WS-C: pelvis and torso peaks within this window (≈1 frame @30fps) make the
    /// downswing peak *order* noise rather than signal — the two segments share the
    /// pose model's yaw component, so a sub-frame gap can't be resolved. The sequence
    /// is then scored neutral (its weight redistributed to the reliable components).
    static let sequenceDegenerateWindow = 0.033

    /// True when pelvis and torso peak essentially together — an unresolvable order.
    static func isSequenceDegenerate(_ seq: KinematicSequence) -> Bool {
        guard seq.peaks.count == 4,
              let pelvis = seq.peaks.first(where: { $0.segment == .pelvis })?.time,
              let torso = seq.peaks.first(where: { $0.segment == .torso })?.time
        else { return false }
        return abs(torso - pelvis) < sequenceDegenerateWindow
    }

    /// WS-C: orientation confidence is judged in the P4/P5 (top/transition) neighborhood,
    /// not averaged over the whole clip — a clean address and impact must not mask a
    /// corrupt top, which is exactly where turn/X-factor/plane are read. Falls back to the
    /// whole-clip fraction when no top/transition checkpoint is available.
    static let orientationWindowSeconds = 0.15

    static func windowedOrientationConfidence(frames: [PoseFrame],
                                              checkpoints: [CheckpointMark]) -> Double {
        windowedFraction(trust: BodyOrientation.orientationTrustMask(frames: frames),
                         times: frames.map(\.time), checkpoints: checkpoints)
    }

    /// Pure windowing math (no pose model) so it can be unit-tested directly: the fraction
    /// of trusted frames within ±`orientationWindowSeconds` of any P4/P5 checkpoint, or the
    /// whole-clip fraction when there's no top/transition anchor or no frames land in-window.
    static func windowedFraction(trust: [Bool], times: [Double],
                                 checkpoints: [CheckpointMark]) -> Double {
        guard !trust.isEmpty else { return 0 }
        let wholeClip = { Double(trust.filter { $0 }.count) / Double(trust.count) }

        let anchors = checkpoints.filter { $0.position == .p4 || $0.position == .p5 }
        guard !anchors.isEmpty else { return wholeClip() }

        var indices = Set<Int>()
        for anchor in anchors {
            for i in times.indices
            where i < trust.count && abs(times[i] - anchor.time) <= orientationWindowSeconds {
                indices.insert(i)
            }
        }
        guard !indices.isEmpty else { return wholeClip() }
        let trustedInWindow = indices.filter { trust[$0] }.count
        return Double(trustedInWindow) / Double(indices.count)
    }

    /// A2: degrade orientation-dependent metrics when the yaw stream is weak. Pure over
    /// the metric list; never touches orientation-independent metrics, never edits the
    /// value. Above `orientationInferredThreshold` this is a no-op.
    static func degradeForOrientation(_ metrics: [MetricValue],
                                      orientationConfidence: Double) -> [MetricValue] {
        guard orientationConfidence < orientationInferredThreshold else { return metrics }
        let withhold = orientationConfidence < orientationWithheldThreshold
        return metrics.map { metric in
            guard orientationDependentMetrics.contains(metric.label) else { return metric }
            let base = metric.quality
                ?? MeasurementQuality(confidence: 0, coverage: 0, provenance: .measured)
            // Only degrade a genuinely measured value — never upgrade one already
            // withheld upstream (e.g. plane with no basis is already `.unavailable`).
            guard base.provenance == .measured else { return metric }
            var metric = metric
            let caveat = withhold
                ? "\(metric.label) depends on 3D body rotation, which was too unsteady through this swing to measure reliably; it was withheld."
                : "\(metric.label) depends on 3D body rotation, which was only partly trusted through this swing; treat it as an estimate."
            metric.quality = MeasurementQuality(
                confidence: withhold ? min(base.confidence, 0.15) : min(base.confidence, 0.5),
                coverage: base.coverage,
                provenance: withhold ? .unavailable : .inferred,
                warnings: base.warnings + [caveat]
            )
            return metric
        }
    }

    // MARK: - Score

    static func score(_ input: Inputs, metrics: [MetricValue],
                      quality: ReportQuality) -> SwingScore {
        func bandScore(_ value: Double, _ lo: Double, _ hi: Double) -> Double {
            guard value < lo || value > hi else { return 1.0 }
            let halfWidth = max(1e-6, (hi - lo) / 2)
            let distance = value < lo ? lo - value : value - hi
            return max(0, 1 - distance / halfWidth)
        }
        func metricScore(_ label: String) -> Double? {
            guard let m = metrics.first(where: { $0.label == label }),
                  // A1/A2: a withheld metric (implausible, or orientation too weak to
                  // trust) is not evidence — it must not contribute to the score.
                  m.quality?.provenance != .unavailable else { return nil }
            return bandScore(m.value, m.idealLow, m.idealHigh)
        }

        // Sequence order (30%): fraction of segments whose peak-time rank matches the
        // ideal pelvis->torso->leadArm->club order. Scored neutral (nil -> weight
        // redistributed to the reliable components) when the order can't be trusted:
        // either the orientation stream was untrusted through the downswing
        // (KinematicSequence.lowConfidence), or the sequence is DEGENERATE — pelvis and
        // torso peaking within one frame, where peak *order* is noise not signal
        // (SegmentSeries's shared-yaw compression). An unmeasured order is neither
        // rewarded nor punished.
        let sequenceScore: Double?
        if input.sequence.peaks.count == 4,
           input.sequence.lowConfidence != true,
           !Self.isSequenceDegenerate(input.sequence) {
            let actual = input.sequence.peaks.sorted { $0.time < $1.time }.map(\.segment)
            let ideal = input.sequence.idealOrder
            let matches = zip(actual, ideal).filter { $0 == $1 }.count
            sequenceScore = Double(matches) / Double(ideal.count)
        } else {
            sequenceScore = nil
        }

        let planeScore = metricScore("Swing Plane")
        let turnScore = [metricScore("Shoulder Turn"), metricScore("Hip Turn")].compactMap { $0 }
        let turnAvg = turnScore.isEmpty ? nil : turnScore.reduce(0, +) / Double(turnScore.count)
        let postureScore = [metricScore("Spine Angle"), metricScore("Spine Angle Change at Impact")].compactMap { $0 }
        let postureAvg = postureScore.isEmpty
            ? nil : postureScore.reduce(0, +) / Double(postureScore.count)
        let tempoScore = metricScore("Tempo")

        var available: [(String, Double, Double)] = []
        if let sequenceScore { available.append(("Sequence", sequenceScore, 0.30)) }
        if input.view != .faceOn, let planeScore {
            available.append(("Plane", planeScore, 0.25))
        }
        if let turnAvg { available.append(("Turn / 6DOF", turnAvg, 0.20)) }
        if let postureAvg { available.append(("Posture", postureAvg, 0.15)) }
        if let tempoScore { available.append(("Tempo", tempoScore, 0.10)) }

        let weightTotal = available.reduce(0) { $0 + $1.2 }
        let components = available.map {
            SwingScore.Component(
                label: $0.0,
                score: $0.1,
                weight: weightTotal > 0 ? $0.2 / weightTotal : 0
            )
        }
        let total = components.reduce(0.0) { $0 + $1.score * $1.weight }
        // A1's "missing link": the score gate now also reads orientation confidence.
        // PlausibilityGate collapses it (to ~0.15) when the 3D-rotation family produces
        // anatomically impossible values, so a high-coverage report full of degenerate
        // yaw — the A0 case — can no longer resolve to a confident total.
        let sufficient = quality.twoDCoverage >= 0.65
            && quality.threeDCoverage >= 0.50
            && quality.checkpointConfidence >= 0.80
            && quality.orientationConfidence >= 0.35
            && components.count >= 3
        return SwingScore(
            total: Int((total * 100).rounded()),
            components: components,
            availability: sufficient ? .available : .insufficientData
        )
    }

    static func reportQuality(_ input: Inputs) -> ReportQuality {
        guard !input.frames.isEmpty else {
            return ReportQuality(
                twoDCoverage: 0, threeDCoverage: 0, checkpointConfidence: 0,
                orientationConfidence: 0, planeBasis: input.plane.basis,
                warnings: ["No usable pose frames were measured."]
            )
        }
        let count = Double(input.frames.count)
        let twoD = Double(input.frames.filter { $0.j2.count >= 8 }.count) / count
        let threeD = Double(input.frames.filter { $0.j3.count >= 8 }.count) / count
        let checkpoint = min(1, Double(input.timing.checkpoints.count) / 10)
        // WS-C: judged over the P4/P5 window, so a corrupt top isn't hidden by a clean
        // address/impact.
        let orientation = windowedOrientationConfidence(
            frames: input.frames, checkpoints: input.timing.checkpoints)
        var warnings: [String] = []
        if twoD < 0.65 { warnings.append("Parts of the golfer were not visible consistently.") }
        if threeD < 0.50 { warnings.append("Depth measurements had limited coverage.") }
        if checkpoint < 0.80 { warnings.append("Several swing checkpoints were uncertain.") }
        if orientation < orientationInferredThreshold {
            warnings.append("3D body rotation was only partly trusted at the top; turn, X-factor, and plane are shown with reduced confidence.")
        }
        if isSequenceDegenerate(input.sequence) {
            warnings.append("Pelvis and torso peaked almost together, so the downswing sequence order couldn't be judged; it wasn't scored.")
        }
        if input.view != .faceOn, input.plane.basis == nil {
            warnings.append("The shaft or ball was not clear enough to establish swing plane.")
        }
        return ReportQuality(
            twoDCoverage: twoD,
            threeDCoverage: threeD,
            checkpointConfidence: checkpoint,
            orientationConfidence: orientation,
            planeBasis: input.plane.basis,
            warnings: warnings
        )
    }

    private static func metricQuality(_ quality: ReportQuality) -> MeasurementQuality {
        return MeasurementQuality(
            confidence: min(quality.twoDCoverage, quality.threeDCoverage),
            coverage: min(quality.twoDCoverage, quality.threeDCoverage),
            provenance: .measured,
            warnings: quality.warnings
        )
    }

    // MARK: - Markers

    static func markers(_ input: Inputs) -> [SwingMarker] {
        var out: [SwingMarker] = []
        var n = 0
        func nextID() -> String { n += 1; return "m\(n)" }

        // P1: posture.
        if let spine = input.spineAngleAtAddressDeg {
            let inBand = (28...40).contains(spine)
            out.append(SwingMarker(id: nextID(), position: .p1, joint: .spine,
                                   kind: inBand ? .good : .fault,
                                   title: inBand ? "Athletic posture" : "Posture off vertical",
                                   detail: String(format: "Spine tilt of %.0f° from vertical at address.%@",
                                                  spine, inBand ? " A neutral, powerful setup." :
                                                  " Outside the 28-40° band that keeps the swing on plane.")))
        }

        // P4: turn / X-factor, and the plane-deviation warning (deviation is measured
        // at P5 but shown at the Top checkpoint, same convention as the design mock).
        // Turn marker gated on orientation trust like the turn metrics — a marker
        // that says "2° of shoulder rotation" off interpolated data is a false claim.
        if input.orientationTrustedAtP4,
           let chestTurn = input.chestDOF[.p4]?.turn, let hipTurn = input.pelvisDOF[.p4]?.turn {
            let cAbs = abs(chestTurn), hAbs = abs(hipTurn)
            let good = cAbs >= 85
            out.append(SwingMarker(id: nextID(), position: .p4, joint: .shoulderR,
                                   kind: good ? .good : .fault,
                                   title: good ? "Full shoulder turn" : "Limited shoulder turn",
                                   detail: String(format: "%.0f° of shoulder rotation against %.0f° of hip turn.%@",
                                                  cAbs, hAbs, good ? " Strong coil and separation." :
                                                  " Under the ~90° benchmark — some power is left on the table.")))
        }
        if let dev = input.plane.deviationByPosition[.p5], let state = input.plane.stateByPosition[.p5], state != .neutral {
            out.append(SwingMarker(id: nextID(), position: .p4, joint: .wristL, kind: .fault,
                                   title: state == .over ? "Over the top" : "Dropping under plane",
                                   detail: String(format: "In transition the club is %.1f° %@ the base plane.",
                                                  abs(dev), state == .over ? "above" : "below")))
        }

        // P7: shaft/plane state at impact-adjacent P6, and pelvis thrust (early
        // extension) when measurable (down-the-line).
        if input.view == .downTheLine || input.view == .fused, let thrust = input.pelvisDOF[.p7]?.thrust {
            let inBand = abs(thrust) <= 1.5
            out.append(SwingMarker(id: nextID(), position: .p7, joint: .hipR,
                                   kind: inBand ? .good : .fault,
                                   title: inBand ? "Posture held through impact" : "Early extension",
                                   detail: String(format: "Pelvis has thrust %.1f in %@ the ball through impact.%@",
                                                  abs(thrust), thrust >= 0 ? "toward" : "away from",
                                                  inBand ? "" : " Standing up like this steepens the shaft and forces compensations.")))
        }
        if let dev = input.plane.deviationByPosition[.p6], let state = input.plane.stateByPosition[.p6] {
            out.append(SwingMarker(id: nextID(), position: .p7, joint: .wristR,
                                   kind: state == .neutral ? .good : .fault,
                                   title: state == .neutral ? "On-plane delivery" : "Off-plane delivery",
                                   detail: String(format: "Shaft is %.1f° from the base plane approaching impact.", dev)))
        }

        // P10: finish turn, if available.
        if let chestTurn = input.chestDOF[.p10]?.turn {
            out.append(SwingMarker(id: nextID(), position: .p10, joint: .shoulderL, kind: .good,
                                   title: "Finish position",
                                   detail: String(format: "Chest has rotated %.0f° from address by the finish.", abs(chestTurn))))
        }
        return out
    }
}

private extension MetricsBuilder.Inputs {
    /// Absolute forward tilt of the chest segment from vertical, at the address
    /// frame itself — single-frame, no cross-frame stabilization needed (model
    /// space's +y is up within any one frame; this isn't the cross-frame turn
    /// problem BodyOrientation.swift documents).
    var spineAngleAtAddressDeg: Double? {
        guard let p1 = timing.checkpoints.first(where: { $0.position == .p1 }),
              p1.frameIndex < frames.count,
              let seg = SegmentSeries.frame(frames[p1.frameIndex], .chest) else { return nil }
        let worldUp = SIMD3<Double>(0, 1, 0)
        let cosA = max(-1, min(1, dot(seg.up, worldUp)))
        return acos(cosA) * 180 / .pi
    }

    /// Whether the body-orientation stream is trusted at (or within ±2 frames of)
    /// P4 — the gate for reporting turn-at-top as a measured metric.
    var orientationTrustedAtP4: Bool {
        guard let p4 = timing.checkpoints.first(where: { $0.position == .p4 }),
              !frames.isEmpty else { return false }
        let trust = BodyOrientation.orientationTrustMask(frames: frames)
        let lo = max(0, p4.frameIndex - 2), hi = min(frames.count - 1, p4.frameIndex + 2)
        guard lo <= hi, hi < trust.count else { return false }
        return (lo...hi).contains { trust[$0] }
    }
}
