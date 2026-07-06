// Deterministic, offline coaching. Evaluates the report against the chain in priority order —
// (1) kinematic sequence, (2) plane deviation at P5/P6, (3) posture (spine angle, early
// extension, sway), (4) tempo, (5) turn magnitude — per docs/SWING_MODEL.md's rule: fix the
// earliest link in the chain first. Never returns zero goals: an all-in-band swing gets
// refinement goals for its tightest margins instead of fabricated faults.
import Foundation

public struct RuleBasedCoach: CoachingEngine {
    public init() {}

    public func coach(_ report: SwingReport, context: CoachingContext) async throws -> CoachingPlan {
        // Metric-family checks read ONLY coachable metrics — a withheld (.unavailable)
        // value is never differenced into a fault. Plane/sequence/posture checks carry
        // their own measurement gates (plane.basis, empty peaks, missing DOF).
        let coachable = report.coachableMetrics
        var violations: [RuleBasedCoach.Violation] = []
        if let v = Self.checkSequence(report.sequence) { violations.append(v) }
        if let v = Self.checkPlane(report.plane) { violations.append(v) }
        if let v = Self.checkPosture(report) { violations.append(v) }
        if let v = Self.checkTempo(coachable) { violations.append(v) }
        if let v = Self.checkTurn(coachable) { violations.append(v) }

        // Low-confidence read: lead with capture quality and never fabricate confidence.
        // At most one measured-fault goal follows, marked tentative. The "≥2 goals" floor
        // is relaxed here — an honest single capture goal beats an invented second fault.
        if !report.score.isAvailable {
            var goals: [CoachGoal] = [Self.captureGoal(report)]
            if let v = violations.first {
                goals.append(Self.goal(from: v, priority: 2, tentative: true))
            }
            return CoachingPlan(
                verdict: "We couldn't measure this one cleanly — get the whole swing in frame and we'll give you a precise read.",
                goals: goals, source: .rules)
        }

        var goals: [CoachGoal] = violations.prefix(4).enumerated().map { index, v in
            Self.goal(from: v, priority: index + 1)
        }

        if goals.count < 2 {
            let usedLabels = Set(violations.map(\.metricLabel))
            let need = 2 - goals.count
            let refinements = Self.refinementGoals(from: coachable, excludingLabels: usedLabels, need: need)
            for r in refinements {
                goals.append(Self.goal(from: r, priority: goals.count + 1))
            }
        }

        // Absolute last resort so we truly never return zero goals, even on a near-empty fixture.
        if goals.isEmpty {
            goals.append(Self.captureGoal(report))
        }

        let verdict = Self.buildVerdict(report: report, primary: violations.first)
        return CoachingPlan(verdict: verdict, goals: goals, source: .rules)
    }

    /// Builds a CoachGoal from a violation, attaching its external-focus cue. `tentative`
    /// softens the detail when the read is low-confidence.
    static func goal(from v: Violation, priority: Int, tentative: Bool = false) -> CoachGoal {
        let detail = tentative
            ? "If this read holds up on a cleaner capture: \(v.detail)"
            : v.detail
        return CoachGoal(priority: priority, title: v.title, detail: detail, metricLabel: v.metricLabel,
                         current: v.current, target: v.target, drill: v.drill.name, drillDetail: v.drill.detail,
                         cue: cue(for: v))
    }

    /// The honest lead when the score is insufficient: how to get a cleaner read, never a
    /// fabricated fault. Sentinel `metricLabel == "Capture"` — the UI treats it as a
    /// non-metric card.
    static func captureGoal(_ report: SwingReport) -> CoachGoal {
        let notes = report.quality?.warnings.first
        let detail = notes.map { "\($0) Re-record with your whole body — head to clubhead — in frame, the phone steady, and even light." }
            ?? "This swing didn't have enough measured checkpoints for specific feedback. Re-record with the full address-to-finish window in view so the plane, sequence, and posture checks all have data to work from."
        return CoachGoal(
            priority: 1, title: "Get a cleaner read",
            detail: detail,
            metricLabel: "Capture", current: "Low confidence", target: "Full swing in frame",
            drill: Drills.mirrorCheckpoints.name, drillDetail: Drills.mirrorCheckpoints.detail,
            cue: "Frame the whole swing in good light")
    }

    /// External-focus, prescriptive caption for a fault — names the club/target/effect,
    /// not a body part. Feeds the on-frame coaching canvas (WS-E).
    static func cue(for v: Violation) -> String {
        switch v.tier {
        case 1: return "Let the club trail the turn coming down"
        case 2: return v.current.lowercased().contains("shallow")
            ? "Bring the club out in front of you"
            : "Drop the club into the corridor"
        case 3: return v.metricLabel.lowercased().contains("sway")
            ? "Turn inside a barrel — don't slide"
            : "Cover the ball through the strike"
        case 4: return v.title.lowercased().contains("sharpen")
            ? "Flow into the downswing a beat sooner"
            : "Finish the backswing before you fire"
        case 5: return "Turn your back to the target at the top"
        default: return "Keep sharpening this one"   // tier 6 refinement (already in-band)
        }
    }

    // MARK: - Internal violation model

    struct Violation {
        let tier: Int
        let title: String
        let detail: String
        let metricLabel: String
        let current: String
        let target: String
        let drill: Drill
        let severity: Double
    }

    // MARK: - Tier 1: kinematic sequence

    static func checkSequence(_ seq: KinematicSequence) -> Violation? {
        guard !seq.peaks.isEmpty else { return nil }
        let actualOrder = seq.peaks.map(\.segment)
        let pelvisTime = seq.peaks.first(where: { $0.segment == .pelvis })?.time
        let torsoTime = seq.peaks.first(where: { $0.segment == .torso })?.time
        let armTime = seq.peaks.first(where: { $0.segment == .leadArm })?.time

        if actualOrder != seq.idealOrder {
            if let armTime, let torsoTime, armTime <= torsoTime {
                return Violation(
                    tier: 1, title: "Sequence hips before arms",
                    detail: "The downswing should unload from the ground up: pelvis, then torso, then arms, then club. Right now the lead arm peaks at \(fmtTime(armTime)) — at or before the torso at \(fmtTime(torsoTime)) — so speed leaks out of order instead of summing into the club.",
                    metricLabel: "Kinematic sequence", current: "Arms early", target: "Pelvis-led",
                    drill: Drills.stepChange, severity: 2.0)
            }
            return Violation(
                tier: 1, title: "Restore the ground-up sequence",
                detail: "An efficient downswing peaks pelvis → torso → lead arm → club, each segment handing energy to the next. Yours peaks \(actualOrder.map(\.rawValue).joined(separator: " → ")) — reorder it from the ground up before anything else, since every later fault traces back to this.",
                metricLabel: "Kinematic sequence",
                current: actualOrder.map(\.rawValue).joined(separator: "→"),
                target: seq.idealOrder.map(\.rawValue).joined(separator: "→"),
                drill: Drills.stepChange, severity: 2.0)
        }

        if let pelvisTime, let torsoTime, (torsoTime - pelvisTime) < 0.03 {
            return Violation(
                tier: 1, title: "Separate hips from shoulders",
                detail: "Pelvis and torso are peaking almost together — \(fmtTime(pelvisTime)) vs \(fmtTime(torsoTime)), only \(fmtTime(torsoTime - pelvisTime)) apart — instead of the pelvis clearly leading. Without that separation the downswing loses the stretch that generates speed and the face loses consistency.",
                metricLabel: "Kinematic sequence", current: "No separation", target: "Pelvis-led",
                drill: Drills.stepChange, severity: 1.5)
        }
        return nil
    }

    // MARK: - Tier 2: swing plane at P5/P6

    static func checkPlane(_ plane: PlaneAnalysis) -> Violation? {
        guard plane.basis != nil else { return nil }  // measurement unavailable — never invent it
        let candidates: [(SwingPosition, Double)] = [.p5, .p6].compactMap { pos in
            plane.deviationByPosition[pos].map { (pos, $0) }
        }
        guard let worst = candidates.max(by: { abs($0.1) < abs($1.1) }) else { return nil }
        let idealBand = 1.5
        guard abs(worst.1) > idealBand else { return nil }

        let state = plane.stateByPosition[worst.0] ?? (worst.1 > 0 ? .over : .under)
        let severity = abs(worst.1) / idealBand
        let label = "Swing plane at \(worst.0.shortName)"

        if state == .under {
            return Violation(
                tier: 2, title: "Get the club back in front of you",
                detail: "At \(worst.0.shortName) the club drops \(fmtDeg(abs(worst.1))) under your base plane and gets trapped behind the body. From here it swings in-to-out through impact, the classic cause of blocks and hooks.",
                metricLabel: label, current: "\(fmtDeg(worst.1)) shallow", target: "±1.5°",
                drill: Drills.headcoverOutsideBall, severity: severity)
        }
        return Violation(
            tier: 2, title: "Shallow the shaft in transition",
            detail: "At \(worst.0.shortName) the club works above your base plane — shaft \(fmtDeg(worst.1)) steep. From here it swings out-to-in through impact, the classic cause of pulls and slices.",
            metricLabel: label, current: "\(fmtDeg(worst.1)) steep", target: "±1.5°",
            drill: Drills.pump, severity: severity)
    }

    // MARK: - Tier 3: posture — spine angle, early extension (pelvis thrust), sway, in that order

    static func checkPosture(_ report: SwingReport) -> Violation? {
        let spineBand = 5.0
        if let bend = report.chestDOF[.p7]?.bend, abs(bend) > spineBand {
            let severity = abs(bend) / spineBand
            return Violation(
                tier: 3, title: "Hold your spine angle to impact",
                detail: "Your chest bend shifts \(fmtDeg(bend)) from address to impact instead of holding — that early rise moves the low point of the swing and forces compensations just to find the ball.",
                metricLabel: "Spine angle change at P7", current: fmtDeg(bend), target: "±5°",
                drill: Drills.chair, severity: severity)
        }

        let thrustBand = 0.5
        if let thrust = report.pelvisDOF[.p7]?.thrust, abs(thrust) > thrustBand {
            let severity = abs(thrust) / thrustBand
            return Violation(
                tier: 3, title: "Hold your pelvis back through impact",
                detail: "The pelvis has thrust \(fmtIn(thrust)) toward the ball, standing you up through impact — classic early extension. Keeping the pelvis back keeps the low point consistent and takes the steepness out of the strike.",
                metricLabel: "Pelvis thrust at P7", current: fmtIn(thrust), target: "±0.5 in",
                drill: Drills.chair, severity: severity)
        }

        let swayBand = 2.0
        let swayEntries = report.pelvisDOF.map { (pos, dof) in (pos, dof.sway) }
        if let worstSway = swayEntries.max(by: { abs($0.1) < abs($1.1) }), abs(worstSway.1) > swayBand {
            let severity = abs(worstSway.1) / swayBand
            return Violation(
                tier: 3, title: "Keep the pivot centered",
                detail: "At \(worstSway.0.shortName) the pelvis has moved \(fmtIn(worstSway.1)) off the ball instead of pivoting in place — that lateral drift costs contact consistency and forces a manual recovery move back to the ball.",
                metricLabel: "Pelvis sway at \(worstSway.0.shortName)", current: fmtIn(worstSway.1), target: "±2.0 in",
                drill: Drills.towelUnderArm, severity: severity)
        }
        return nil
    }

    // MARK: - Tier 4: tempo

    static func checkTempo(_ metrics: [MetricValue]) -> Violation? {
        guard let m = metrics.first(where: { $0.label.lowercased().contains("tempo") }), !m.inBand else { return nil }
        let sev = severity(for: m)
        let mid = (m.idealLow + m.idealHigh) / 2
        if m.value > m.idealHigh {
            return Violation(
                tier: 4, title: "Sharpen the transition",
                detail: "Your backswing-to-downswing ratio is \(fmtRatio(m.value)), slower than the \(fmtRatio(mid)) tour benchmark — there's speed being left on the table in transition.",
                metricLabel: m.label, current: fmtRatio(m.value), target: "\(fmtRatio(m.idealLow))–\(fmtRatio(m.idealHigh))",
                drill: Drills.pauseAtTop, severity: sev)
        }
        return Violation(
            tier: 4, title: "Slow the transition down",
            detail: "Your backswing-to-downswing ratio is \(fmtRatio(m.value)) against a \(fmtRatio(mid)) benchmark — the downswing is rushing the transition, a top cause of sequence breakdown.",
            metricLabel: m.label, current: fmtRatio(m.value), target: "\(fmtRatio(m.idealLow))–\(fmtRatio(m.idealHigh))",
            drill: Drills.pauseAtTop, severity: sev)
    }

    // MARK: - Tier 5: turn magnitude

    static func checkTurn(_ metrics: [MetricValue]) -> Violation? {
        let candidates = metrics.filter { m in
            let l = m.label.lowercased()
            return l.contains("shoulder turn") || l.contains("hip turn") || l.contains("x-factor") || l.contains("separation")
        }
        let violating = candidates.filter { !$0.inBand }
        guard let worst = violating.max(by: { severity(for: $0) < severity(for: $1) }) else { return nil }
        let sev = severity(for: worst)
        return Violation(
            tier: 5, title: "Turn fully before you swing down",
            detail: "\(worst.label) measures \(fmtDeg(worst.value)) against an ideal \(fmtDeg(worst.idealLow))–\(fmtDeg(worst.idealHigh)) — the extra coil that's missing is power the downswing has to manufacture with the arms instead of releasing from the turn.",
            metricLabel: worst.label, current: fmtDeg(worst.value),
            target: "\(fmtDeg(worst.idealLow))–\(fmtDeg(worst.idealHigh))",
            drill: Drills.feetTogether, severity: sev)
    }

    // MARK: - Refinement mode (all-in-band, or too few violations)

    static func refinementGoals(from metrics: [MetricValue], excludingLabels: Set<String>, need: Int) -> [Violation] {
        guard need > 0 else { return [] }
        let candidates = metrics.filter { !excludingLabels.contains($0.label) && $0.idealHigh > $0.idealLow }
        let scored = candidates.map { m -> (MetricValue, Double) in
            let bandWidth = m.idealHigh - m.idealLow
            let marginToEdge = min(m.value - m.idealLow, m.idealHigh - m.value)
            let ratio = bandWidth > 0 ? marginToEdge / bandWidth : 1
            return (m, ratio)
        }.sorted { $0.1 < $1.1 }

        return scored.prefix(need).map { m, _ in
            Violation(
                tier: 6, title: "Tighten \(m.label.lowercased())",
                detail: "\(m.label) sits at \(fmtGeneric(m)) — inside the ideal \(fmtBand(m)) band, but with the least margin of any metric in this swing. Keep sharpening it and it becomes a strength instead of a watch item.",
                metricLabel: m.label, current: fmtGeneric(m), target: fmtBand(m),
                drill: Drills.forLabel(m.label), severity: 0)
        }
    }

    // MARK: - Verdict

    static func buildVerdict(report: SwingReport, primary: Violation?) -> String {
        guard let primary else {
            let best = report.score.components.max(by: { $0.score < $1.score })
            let strength = best.map { strengthPhrase(for: $0.label) } ?? "A tight, repeatable action"
            return "\(strength) — every measurement is inside its ideal band, so the next gains come from tightening margins, not fixing faults."
        }
        let category = categoryForTier[primary.tier]
        let candidates = report.score.components.filter { comp in
            guard let category else { return true }
            return !comp.label.lowercased().contains(category)
        }
        let pool = candidates.isEmpty ? report.score.components : candidates
        let best = pool.max(by: { $0.score < $1.score })
        let strength = best.map { strengthPhrase(for: $0.label) } ?? "A compact, repeatable action"
        return "\(strength) — \(faultClause(primary))."
    }

    static let categoryForTier: [Int: String] = [1: "sequence", 2: "plane", 3: "posture", 4: "tempo", 5: "turn"]

    static func strengthPhrase(for label: String) -> String {
        let l = label.lowercased()
        if l.contains("sequence") { return "Efficiently sequenced from the ground up" }
        if l.contains("plane") { return "A clean, neutral swing plane" }
        if l.contains("posture") { return "Rock-solid posture through the swing" }
        if l.contains("tempo") { return "Tour-caliber tempo" }
        if l.contains("turn") { return "A full, powerful turn" }
        return "A compact, repeatable action"
    }

    static func faultClause(_ v: Violation) -> String {
        switch v.tier {
        case 1: return "the downswing sequence breaks down before the arms take over"
        case 2: return "the shaft comes off plane in transition, \(v.current.lowercased())"
        case 3: return "posture leaks late in the swing, \(v.current.lowercased())"
        case 4: return "the transition timing is off, \(v.current.lowercased())"
        default: return "the turn falls short of full power, \(v.current.lowercased())"
        }
    }
}

// MARK: - Formatting helpers

func fmtDeg(_ v: Double, decimals: Int = 1) -> String {
    let sign = v >= 0 ? "+" : ""
    return String(format: "%@%.\(decimals)f°", sign, v)
}

func fmtIn(_ v: Double) -> String {
    let sign = v >= 0 ? "+" : ""
    return String(format: "%@%.1f in", sign, v)
}

func fmtRatio(_ v: Double) -> String {
    String(format: "%.1f:1", v)
}

func fmtTime(_ v: Double) -> String {
    String(format: "%.2fs", v)
}

func fmtGeneric(_ m: MetricValue) -> String {
    String(format: "%.1f%@", m.value, m.unit)
}

func fmtBand(_ m: MetricValue) -> String {
    String(format: "%.1f–%.1f%@", m.idealLow, m.idealHigh, m.unit)
}

func severity(for m: MetricValue) -> Double {
    if m.inBand { return 0 }
    let overshoot = m.value < m.idealLow ? (m.idealLow - m.value) : (m.value - m.idealHigh)
    let halfWidth = (m.idealHigh - m.idealLow) / 2
    return halfWidth > 0 ? overshoot / halfWidth : 1
}
