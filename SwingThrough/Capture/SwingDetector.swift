// Auto swing detection — no record button. A small, honest state machine over the live
// grip track:
//
//   idle ──(checklist green + still address ≥1.0s)──▶ ready (armed)
//   ready ──(grip speed ≥ 0.9 u/s, 2 consecutive samples)──▶ capturing   [trigger]
//   capturing ──(speed < 0.30 u/s)──▶ settling
//   settling ──(quiet holds 1.5s)──▶ captured        (spike → back to capturing)
//   ready ──(posture stands up · walks off · checklist breaks · 45s timeout)──▶ idle
//
// Units are image fractions per second on the median-filtered grip point (wrist
// midpoint). Thresholds were tuned against the bundled DTL fixture: address noise
// < 0.12 u/s, takeaway 0.2–0.7, downswing > 2, follow-through decay < 0.3 by half a
// second after impact. The 3-sample median kills Vision's single-frame glitches
// (observed 1.2–2.0 u/s spikes mid-address); the two-consecutive-samples trigger rule
// survives the position jump when a looping file feed wraps.
//
// Recording contract: the take starts retaining media at stillness onset (so the file
// always holds the address), and `captured` reports the exact trim — pre-roll 1.5s
// before the trigger through 1.0s into the settle.
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
        var triggerSpeed = 0.9        // u/s, must hold for `triggerSamples`
        var triggerSamples = 2
        var settleSpeed = 0.30        // u/s — swing energy gone
        var settleHold = 1.5          // s under settleSpeed to finish
        var preRoll = 1.5             // s kept before the trigger
        var settleTail = 1.0          // s of the settle kept after the swing
        var uprightSpineMax = 20.0    // deg from vertical; below = standing, not addressing
        var postureHold = 0.5         // s standing-straight before disarm (DTL only)
        var walkSpeed = 0.18          // u/s of bbox center-x = walking through frame
        var walkHold = 0.4
        var lostAfter = 0.6           // s without a grip point in ready → disarm
        var armedTimeout = 45.0       // s armed with no swing → recycle the take
        var maxCapture = 12.0         // s hard stop on a runaway capture
    }

    struct Input {
        var time: Double              // monotonic feed clock
        var sourceTime: Double        // media time (wraps on a looping feed)
        var grip: SIMD2<Double>?
        var bboxCenterX: Double?
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
    private var captureStart: Double?
    private var settleSince: (t: Double, source: Double)?
    private var uprightSince: Double?
    private var walkSince: Double?
    private var gripSeenAt = -Double.infinity
    private var centerX: (t: Double, x: Double, v: Double)?
    private var manual = false

    func reset() {
        phase = .idle(hold: 0)
        gripWindow = []; lastFiltered = nil; lastSourceTime = -.infinity
        stillSince = nil; recordArmed = false; armedAt = nil
        fastStreak = 0; triggerSource = nil; captureStart = nil; settleSince = nil
        uprightSince = nil; walkSince = nil; gripSeenAt = -.infinity
        centerX = nil; manual = false; gripSpeed = 0
    }

    /// Manual fallback (countdown record): jump straight to capturing. The trim starts
    /// at `sourceTime`; the swing-then-settle logic still ends it, with the 12s cap as
    /// the guardrail. Caller must have issued beginTake.
    func beginManualCapture(input: Input) -> [Event] {
        reset()
        manual = true
        recordArmed = true
        triggerSource = input.sourceTime + config.preRoll   // trimFrom = sourceTime
        captureStart = input.time
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
        guard let x = input.bboxCenterX else {
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
            let hold = (input.time - stillSince!) / config.armHold
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
        // Trigger first: a swing beats every disarm rule.
        if gripSpeed >= config.triggerSpeed {
            fastStreak += 1
            if fastStreak >= config.triggerSamples {
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
        if !input.checklistGreen { return .checklist }
        if input.time - gripSeenAt > config.lostAfter { return .lost }
        if let armedAt, input.time - armedAt > config.armedTimeout { return .timeout }

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
        let settleStart = settleSince?.source ?? input.sourceTime
        phase = .captured
        recordArmed = false
        return [.captured(trimFrom: trigger - config.preRoll,
                          trimTo: settleStart + config.settleTail)]
    }
}
