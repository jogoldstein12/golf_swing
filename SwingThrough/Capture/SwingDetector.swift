// Auto swing detection — no record button. A small, honest state machine over the live
// grip track:
//
//   idle ──(checklist green + still address ≥1.0s)──▶ ready (armed)
//   ready ──(grip ≥1.0 u/s once, or ≥0.7 twice running)──▶ capturing     [trigger]
//   capturing ──(speed < 0.30 u/s)──▶ settling
//   settling ──(quiet holds 1.5s)──▶ captured        (spike → back to capturing)
//   ready ──(posture stands up · walks off · checklist breaks · 45s timeout)──▶ idle
//
// Units are image fractions per second on the median-filtered, confidence-weighted
// grip point. Thresholds were tuned against the bundled DTL fixture through the real
// pipeline (~12.5Hz effective, EMA-smoothed): address noise < 0.1 u/s, waggle-scale
// motion < 0.45, backswing 0.2–0.75, downswing ≥ 1.19. The 3-sample median kills
// Vision's single-frame glitches, and a looping feed's wrap never enters the speed
// trace (the source-clock jump resets the filter first).
//
// Recording contract: the take starts retaining media at stillness onset (so the file
// always holds the address), and `captured` reports the exact trim — the earlier of
// 1.5s before the trigger or 1.0s before the takeaway's motion run began, through
// 1.0s into the settle. A slow backswing must not push the address out of the file.
import Foundation
import simd

final class SwingDetector {
    // MARK: - Public surface

    enum Phase: Equatable {
        case idle(hold: Double)       // hold: 0…1 progress of the address-stillness gate
        case ready
        case capturing
        case settling(Double)         // 0…1 progress of the quiet-hold gate
        case captured
    }

    enum DisarmReason: Equatable {
        case checklist, posture, walking, lost, timeout, sceneCut
    }

    enum Event: Equatable {
        case recordStart              // begin retaining media (provisional)
        case recordCancel             // discard it
        case armed
        case disarmed(DisarmReason)
        case triggered
        /// Final trim, in source-media time.
        case captured(trimFrom: Double, trimTo: Double)
    }

    struct Config {
        var stillSpeed = 0.12         // u/s — "holding address"
        var armHold = 1.0             // s of stillness to arm
        /// Trigger is two-tier: one sample at the high bar (a downswing is unmistakable
        /// even through the EMA), or two consecutive at the low bar (sustained swing
        /// motion). Waggles top out ~0.45; the fixture's slow backswing ~0.75.
        var triggerHigh = 1.0         // u/s, single sample
        var triggerSpeed = 0.7        // u/s, must hold for `triggerSamples`
        var triggerSamples = 2
        var settleSpeed = 0.30        // u/s — swing energy gone
        var settleHold = 1.5          // s under settleSpeed to finish
        var preRoll = 1.5             // s kept before the trigger
        /// Seconds of held address kept before the swing's motion run began. The trim
        /// takes whichever reaches further back, `preRoll` before the trigger or this
        /// before the takeaway — a slow backswing must not push the address out of
        /// the file.
        var addressLead = 1.0
        var settleTail = 1.0          // s of the settle kept after the swing
        var uprightSpineMax = 20.0    // deg from vertical; below = standing, not addressing
        var postureHold = 0.5         // s standing-straight before disarm (DTL only)
        var walkSpeed = 0.18          // u/s of hip center-x = walking through frame
        var walkHold = 0.4
        /// Setup rules (posture / walk-off / checklist) only judge a body at sustained
        /// rest: grip under `restSpeed` for at least `restHold`. A backswing dips slow
        /// at the top — instantaneous speed gating would re-arm the setup rules
        /// mid-swing and a flapping chip would kill the capture.
        var restSpeed = 0.18
        var restHold = 0.35
        /// Chaos override: checklist red this long disarms even without rest
        /// (someone walked into frame and stayed there, light died, etc.).
        var checklistRedMax = 2.5
        var lostAfter = 0.6           // s without a grip point in ready → disarm
        var armedTimeout = 45.0       // s armed with no swing → recycle the take
        var maxCapture = 12.0         // s hard stop on a runaway capture
    }

    struct Input {
        var time: Double              // monotonic feed clock
        var sourceTime: Double        // media time (wraps on a looping feed)
        var grip: SIMD2<Double>?
        /// Hip/pelvis center x — a locomotion signal. (Not the bbox center: that
        /// includes the wrists, and a backswing would read as walking.)
        var hipCenterX: Double?
        var spineFromVerticalDeg: Double?
        var checklistGreen: Bool
        var requirePosture: Bool      // DTL only
    }

    var config = Config()
    private(set) var phase: Phase = .idle(hold: 0)
    /// Smoothed grip speed, exposed for debug HUDs.
    private(set) var gripSpeed: Double = 0

    // MARK: - Internals

    private var gripWindow: [SIMD2<Double>] = []   // last 3 raw grips (median filter)
    private var lastFiltered: (t: Double, p: SIMD2<Double>)?
    private var lastSourceTime = -Double.infinity
    private var stillSince: Double?
    private var recordArmed = false                // beginTake issued
    private var armedAt: Double?
    private var fastStreak = 0
    private var triggerSource: Double?
    /// Source time where the current motion run began (ready state only) — the
    /// takeaway, if a trigger follows. A run only ends after sustained quiet
    /// (`runQuietReset`): the club pausing at the top of a slow backswing is part of
    /// the swing, not a re-address.
    private var runStartSource: Double?
    private var runLowSince: Double?
    private let runQuietReset = 0.4
    private var captureStart: Double?
    private var manualAwaitingMotion = false
    private var settleSince: (t: Double, source: Double)?
    private var uprightSince: Double?
    private var walkSince: Double?
    private var quietSince: Double?
    private var checklistRedSince: Double?
    private var gripSeenAt = -Double.infinity
    private var centerX: (t: Double, x: Double, v: Double)?

    func reset() {
        phase = .idle(hold: 0)
        gripWindow = []; lastFiltered = nil; lastSourceTime = -.infinity
        stillSince = nil; recordArmed = false; armedAt = nil
        fastStreak = 0; triggerSource = nil; runStartSource = nil; runLowSince = nil
        captureStart = nil; settleSince = nil
        manualAwaitingMotion = false
        uprightSince = nil; walkSince = nil; quietSince = nil
        checklistRedSince = nil; gripSeenAt = -.infinity
        centerX = nil; gripSpeed = 0
    }

    /// Manual fallback (countdown record): retain immediately, but do not allow the
    /// settle detector to finish until real swing motion has occurred. This prevents
    /// a pre-shot pause from producing a short, swing-less clip.
    func beginManualCapture(input: Input) -> [Event] {
        reset()
        recordArmed = true
        triggerSource = input.sourceTime + config.preRoll   // trimFrom = sourceTime
        captureStart = input.time
        manualAwaitingMotion = true
        phase = .capturing
        return [.triggered]
    }

    func ingest(_ input: Input) -> [Event] {
        var events: [Event] = []

        // A looping feed wrapping its source clock is a scene cut: whatever we were
        // tracking no longer exists in one contiguous piece of media.
        if input.sourceTime < lastSourceTime - 0.5 {
            if recordArmed { events.append(.recordCancel) }
            let wasWorking = phase != .idle(hold: 0)
            reset()
            if wasWorking { events.append(.disarmed(.sceneCut)) }
            lastSourceTime = input.sourceTime
            return events
        }
        lastSourceTime = input.sourceTime

        updateSpeed(input)
        updateWalk(input)

        switch phase {
        case .idle:
            events += stepIdle(input)
        case .ready:
            events += stepReady(input)
        case .capturing:
            events += stepCapturing(input)
        case .settling:
            events += stepSettling(input)
        case .captured:
            break
        }
        return events
    }

    // MARK: - Signal conditioning

    private func updateSpeed(_ input: Input) {
        guard let grip = input.grip else { return }
        gripSeenAt = input.time
        gripWindow.append(grip)
        if gripWindow.count > 3 { gripWindow.removeFirst() }
        let filtered = SIMD2(median(gripWindow.map(\.x)), median(gripWindow.map(\.y)))
        defer { lastFiltered = (input.time, filtered) }
        guard let last = lastFiltered, input.time > last.t else { return }
        let raw = simd_distance(filtered, last.p) / (input.time - last.t)
        gripSpeed += 0.45 * (raw - gripSpeed)      // EMA
    }

    private func median(_ v: [Double]) -> Double {
        let s = v.sorted()
        return s[s.count / 2]
    }

    private func updateWalk(_ input: Input) {
        guard let x = input.hipCenterX else {
            centerX = nil
            return
        }
        if let last = centerX, input.time > last.t {
            let v = abs(x - last.x) / (input.time - last.t)
            centerX = (input.time, x, last.v + 0.4 * (v - last.v))
        } else {
            centerX = (input.time, x, 0)
        }
    }

    // MARK: - Phases

    private func stepIdle(_ input: Input) -> [Event] {
        var events: [Event] = []
        let postured = !input.requirePosture
            || (input.spineFromVerticalDeg ?? 90) > config.uprightSpineMax
        let holding = input.checklistGreen && postured
            && input.grip != nil && gripSpeed < config.stillSpeed

        if holding {
            if stillSince == nil {
                stillSince = input.time
                if !recordArmed {
                    recordArmed = true
                    events.append(.recordStart)
                }
            }
            let hold = (input.time - (stillSince ?? input.time)) / config.armHold
            if hold >= 1 {
                phase = .ready
                armedAt = input.time
                fastStreak = 0
                events.append(.armed)
            } else {
                phase = .idle(hold: hold)
            }
        } else {
            if recordArmed {
                recordArmed = false
                events.append(.recordCancel)
            }
            stillSince = nil
            phase = .idle(hold: 0)
        }
        return events
    }

    private func stepReady(_ input: Input) -> [Event] {
        // Track when the current motion run started — that's the takeaway if this
        // run turns out to be the swing.
        if gripSpeed >= config.stillSpeed {
            runLowSince = nil
            runStartSource = runStartSource ?? input.sourceTime
        } else {
            runLowSince = runLowSince ?? input.time
            if input.time - runLowSince! >= runQuietReset {
                runStartSource = nil
            }
        }

        // Trigger first: a swing beats every disarm rule.
        if gripSpeed >= config.triggerSpeed {
            fastStreak += 1
            if gripSpeed >= config.triggerHigh || fastStreak >= config.triggerSamples {
                triggerSource = input.sourceTime
                captureStart = input.time
                settleSince = nil
                phase = .capturing
                return [.triggered]
            }
            return []
        }
        fastStreak = 0

        if let reason = disarmReason(input) {
            recordArmed = false
            stillSince = nil
            phase = .idle(hold: 0)
            return [.recordCancel, .disarmed(reason)]
        }
        return []
    }

    private func disarmReason(_ input: Input) -> DisarmReason? {
        // Ungated safety rules.
        if input.time - gripSeenAt > config.lostAfter { return .lost }
        if let armedAt, input.time - armedAt > config.armedTimeout { return .timeout }

        if gripSpeed < config.restSpeed {
            quietSince = quietSince ?? input.time
        } else {
            quietSince = nil
        }
        checklistRedSince = input.checklistGreen ? nil
            : (checklistRedSince ?? input.time)

        // Chaos override — a long-red checklist disarms even mid-motion.
        if let red = checklistRedSince,
           input.time - red >= config.checklistRedMax { return .checklist }

        // Everything else only judges a body at sustained rest; a swing in progress
        // is not a framing problem.
        guard let quiet = quietSince,
              input.time - quiet >= config.restHold else {
            uprightSince = nil
            walkSince = nil
            return nil
        }
        if checklistRedSince != nil { return .checklist }

        if input.requirePosture, let spine = input.spineFromVerticalDeg,
           spine < config.uprightSpineMax {
            uprightSince = uprightSince ?? input.time
            if input.time - uprightSince! >= config.postureHold { return .posture }
        } else {
            uprightSince = nil
        }

        if let c = centerX, c.v > config.walkSpeed {
            walkSince = walkSince ?? input.time
            if input.time - walkSince! >= config.walkHold { return .walking }
        } else {
            walkSince = nil
        }
        return nil
    }

    private func stepCapturing(_ input: Input) -> [Event] {
        if manualAwaitingMotion {
            if let start = captureStart, input.time - start > config.maxCapture {
                reset()
                return [.recordCancel, .disarmed(.timeout)]
            }
            if gripSpeed >= config.triggerSpeed {
                manualAwaitingMotion = false
            }
            return []
        }
        if let start = captureStart, input.time - start > config.maxCapture {
            return finish(at: input)
        }
        if gripSpeed < config.settleSpeed {
            settleSince = (input.time, input.sourceTime)
            phase = .settling(0)
        }
        return []
    }

    private func stepSettling(_ input: Input) -> [Event] {
        if let start = captureStart, input.time - start > config.maxCapture {
            return finish(at: input)
        }
        guard gripSpeed < config.settleSpeed else {
            settleSince = nil
            phase = .capturing
            return []
        }
        guard let settle = settleSince else { return [] }
        let progress = (input.time - settle.t) / config.settleHold
        if progress >= 1 {
            return finish(at: input)
        }
        phase = .settling(progress)
        return []
    }

    private func finish(at input: Input) -> [Event] {
        let trigger = triggerSource ?? input.sourceTime
        let takeaway = runStartSource ?? trigger
        let settleStart = settleSince?.source ?? input.sourceTime
        phase = .captured
        recordArmed = false
        return [.captured(trimFrom: min(trigger - config.preRoll,
                                        takeaway - config.addressLead),
                          trimTo: settleStart + config.settleTail)]
    }
}
