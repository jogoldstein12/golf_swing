// WS-E — the fault→drawing resolver. Turns "this goal, this report" into "seek to this
// checkpoint, draw these honest primitives, say this cue". The ONE place that decides what
// the coaching canvas is allowed to draw — and it is allowed to draw nothing it hasn't
// measured. A withheld (.unavailable) metric never yields a drawing primitive; the target
// is either a corridor derived from the known ideal band, or a GHOST of the user's own
// prior clean swing — never a synthesized "ideal body".
import Foundation

public enum SkillLevel: String, Sendable, Codable {
    case beginner, intermediate, advanced
}

/// A honest drawing primitive over the frame. Geometry is expressed in the same
/// plane-angle space the pipeline measures (degrees from horizontal); the view layer maps
/// it to screen coordinates.
public enum OverlayPrimitive: Sendable, Equatable {
    /// The user's measured plane at the checkpoint (base plane + deviation).
    case actualPlaneLine(angle: Double, state: PlaneState)
    /// The on-plane target band, from the metric's known ideal range. Shown when there is
    /// no clean prior swing to ghost against.
    case targetCorridor(low: Double, high: Double)
    /// Held reference line from address (spine) — advanced depth.
    case heldReferenceLine
    /// Grip/club path trace — advanced depth.
    case pathTrace
    /// The user's OWN prior clean swing at this checkpoint (feedforward self-model).
    case ghostClub(priorAngle: Double)
    /// "Move here" from the current line toward the ghost.
    case moveArrow(fromAngle: Double, toAngle: Double)

    public var isPlaneLine: Bool { if case .actualPlaneLine = self { return true }; return false }
    public var isCorridor: Bool { if case .targetCorridor = self { return true }; return false }
    public var isGhost: Bool { if case .ghostClub = self { return true }; return false }
}

/// What the canvas should render for one goal.
public struct OverlayPlan: Sendable, Equatable {
    /// The checkpoint the scrubber seeks to when the goal is tapped.
    public var position: SwingPosition
    /// Primitives visible at the current skill level (novice = minimal).
    public var primitives: [OverlayPrimitive]
    /// External-focus caption for the overlay.
    public var caption: String
    /// Extra primitives revealed behind the "more lines" disclosure.
    public var advancedOnly: [OverlayPrimitive]

    public init(position: SwingPosition, primitives: [OverlayPrimitive],
                caption: String, advancedOnly: [OverlayPrimitive]) {
        self.position = position; self.primitives = primitives
        self.caption = caption; self.advancedOnly = advancedOnly
    }
}

public enum SwingOverlay {

    /// Resolve the drawing plan for a goal. `prior` is the user's most recent clean
    /// same-club/same-view swing (or nil). Never draws for a withheld metric.
    public static func plan(goal: CoachGoal, report: SwingReport,
                            prior: SwingReport?, skill: SkillLevel) -> OverlayPlan {
        let position = checkpoint(for: goal)
        let caption = goal.cue ?? derivedCue(from: goal.title)

        var core: [OverlayPrimitive] = []
        // Held reference + path trace are honest (from measured pose) but are depth, not
        // the novice's one-cue default.
        let advanced: [OverlayPrimitive] = [.heldReferenceLine, .pathTrace]

        // The plane overlay is the only primitive with real on-frame geometry today, and
        // only when the plane goal's metric is still trusted.
        if let metric = resolveMetric(goal, in: report),
           isPlaneGoal(goal),
           report.plane.basis != nil,
           (metric.quality?.provenance ?? .measured) != .unavailable {
            let angle = report.plane.basePlaneAngle + metric.value
            let state = report.plane.stateByPosition[position] ?? (metric.value > 0 ? .over : .under)
            core.append(.actualPlaneLine(angle: angle, state: state))

            // Reference: ghost the user's OWN clean prior swing when we have one, else the
            // known target corridor. Never both.
            if let ghostAngle = priorGhostAngle(goal, prior: prior) {
                core.append(.ghostClub(priorAngle: ghostAngle))
                core.append(.moveArrow(fromAngle: angle, toAngle: ghostAngle))
            } else {
                core.append(.targetCorridor(low: report.plane.basePlaneAngle + metric.idealLow,
                                            high: report.plane.basePlaneAngle + metric.idealHigh))
            }
        }

        let primitives = (skill == .beginner) ? core : core + advanced
        return OverlayPlan(position: position, primitives: primitives,
                           caption: caption, advancedOnly: advanced)
    }

    // MARK: - Resolution

    /// The coachable metric a goal is grounded in, matched by label family. Reads
    /// `coachableMetrics` so a withheld metric is never resolved (and never drawn).
    static func resolveMetric(_ goal: CoachGoal, in report: SwingReport) -> MetricValue? {
        let target = goal.metricLabel.lowercased()
        // Prefer an exact/substring label match among the metrics still trusted.
        if let hit = report.coachableMetrics.first(where: {
            target.contains($0.label.lowercased()) || $0.label.lowercased().contains(target)
        }) { return hit }
        // Fall back to family keywords (e.g. "Swing plane at P5" → "Swing Plane").
        if target.contains("plane") {
            return report.coachableMetrics.first { $0.label.lowercased().contains("plane") }
        }
        return nil
    }

    static func isPlaneGoal(_ goal: CoachGoal) -> Bool {
        goal.metricLabel.lowercased().contains("plane")
    }

    /// The checkpoint the fault is best seen at.
    static func checkpoint(for goal: CoachGoal) -> SwingPosition {
        let l = goal.metricLabel.lowercased()
        if l.contains("plane") { return .p5 }
        if l.contains("sequence") { return .p5 }
        if l.contains("turn") || l.contains("x-factor") || l.contains("separation") { return .p4 }
        if l.contains("thrust") || l.contains("spine") || l.contains("posture") || l.contains("sway") { return .p7 }
        if l.contains("tempo") { return .p4 }
        return .p4
    }

    /// The prior swing's plane angle at this fault, but only when that prior read is CLEAN
    /// (`.measured`) — a distrusted prior is not an honest ghost.
    static func priorGhostAngle(_ goal: CoachGoal, prior: SwingReport?) -> Double? {
        guard let prior,
              prior.plane.basis != nil,
              let m = resolveMetric(goal, in: prior),
              (m.quality?.provenance ?? .measured) == .measured
        else { return nil }
        return prior.plane.basePlaneAngle + m.value
    }

    /// Fallback caption when a goal predates `CoachGoal.cue`. Keeps it external-ish.
    static func derivedCue(from title: String) -> String {
        let t = title.lowercased()
        if t.contains("shallow") { return "Drop the club into the corridor" }
        if t.contains("front") || t.contains("trapped") { return "Bring the club out in front of you" }
        if t.contains("turn") || t.contains("coil") { return "Turn your back to the target at the top" }
        return "Match the club to the target line"
    }
}
