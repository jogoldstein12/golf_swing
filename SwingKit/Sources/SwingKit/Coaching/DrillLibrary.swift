// A small curated drill library. Each drill is matched to the fault it fixes; RuleBasedCoach
// picks from these by name rather than generating free-text drills, so the CLI/app can rely on
// a stable, recognizable set. ClaudeCoach is free to write its own drill text — grounded in the
// same swing model — since it isn't limited to a fixed catalog.
import Foundation

public struct Drill: Sendable {
    public let name: String
    public let detail: String
}

public enum Drills {
    public static let pump = Drill(
        name: "Pump drill",
        detail: "Pause at the top, drop your hands to the trail pocket, then fire — three reps before every full swing until the shallow feel is automatic.")

    public static let stepChange = Drill(
        name: "Step-change drill",
        detail: "Start the downswing with a small step toward the target with your lead foot before the arms move at all — it forces the pelvis to lead.")

    public static let chair = Drill(
        name: "Chair drill",
        detail: "Set a chair back against your trail hip at address. Swing to impact without your seat losing contact with the chair.")

    public static let towelUnderArm = Drill(
        name: "Towel-under-arm drill",
        detail: "Trap a towel or headcover under your lead armpit through the takeaway and downswing — if it drops, the arms have disconnected from the turn.")

    public static let splitHandTakeaway = Drill(
        name: "Split-hand takeaway drill",
        detail: "Grip with your hands two inches apart and make slow takeaways to the top — an early wrist hinge or arm-only start shows up immediately.")

    public static let feetTogether = Drill(
        name: "Feet-together drill",
        detail: "Swing at three-quarter speed with your feet together — it forces the pelvis and torso to turn as a unit and rebuilds coil without lower-body sway.")

    public static let pauseAtTop = Drill(
        name: "Pause-at-the-top drill",
        detail: "Swing to the top, hold for a full second, then start down — resets the backswing-to-downswing ratio toward 3:1.")

    public static let headcoverOutsideBall = Drill(
        name: "Headcover-outside-ball drill",
        detail: "Place a headcover a hand's width outside your ball on the target line. Swing down without clipping it to retrain the path back toward neutral.")

    public static let mirrorCheckpoints = Drill(
        name: "Mirror checkpoint drill",
        detail: "Rehearse address, takeaway, and the top in front of a mirror, checking each position against the model before adding speed.")

    /// Best-effort lookup by fault label, for the refinement path where no fixed tier owns the drill.
    public static func forLabel(_ label: String) -> Drill {
        let l = label.lowercased()
        if l.contains("plane") { return pump }
        if l.contains("sequence") { return stepChange }
        if l.contains("spine") || l.contains("posture") || l.contains("thrust") || l.contains("extension") { return chair }
        if l.contains("sway") { return towelUnderArm }
        if l.contains("tempo") { return pauseAtTop }
        if l.contains("turn") || l.contains("hip") || l.contains("shoulder") || l.contains("x-factor") || l.contains("separation") {
            return feetTogether
        }
        if l.contains("takeaway") { return splitHandTakeaway }
        return mirrorCheckpoints
    }
}
