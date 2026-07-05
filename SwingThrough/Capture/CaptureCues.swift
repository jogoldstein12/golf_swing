// Audible + spoken capture cues. This is the first audio in the app: a tiny helper that
// owns an AVSpeechSynthesizer and a couple of short system chimes, and speaks the manual
// countdown. It is a PURE CONSUMER of detector events — it never calls back into the
// detector, never touches its config, and never runs on the frame path beyond the single
// main-actor hop the events already make. Cues fire exactly once per transition because
// the detector emits each event once; there is no dedup here to get wrong.
//
// Silent switch / accessibility: the session uses the `.ambient` category, so every cue
// (speech and chime) is silenced by the hardware mute switch and mixes with — rather than
// stops — the user's own audio. The audio-cues toggle in Settings gates ALL audio here.
// Haptics do NOT follow that toggle: they live at the call sites in CaptureController and
// stay on regardless, because they are silent, private, and the pre-existing behavior —
// muting audio should not also remove the tactile confirmation a golfer feels mid-setup.
import AVFoundation
import AudioToolbox
import Foundation

/// Pure, testable classification of a detector event into the cue it should produce.
/// Kept separate from any audio so the mapping can be unit-tested with no session.
enum CueKind: Equatable {
    case armed             // you are set / armed — chime + spoken confirmation
    case recordingStarted  // swing detected, recording
    case swingCaptured     // swing captured
}

@MainActor
final class CaptureCues {
    /// Settings toggle key. Absent (never set) reads as ON — audio cues are a default-on
    /// affordance that the silent switch still governs.
    static let audioCuesDefaultsKey = "capture.audioCues"

    private let synth = AVSpeechSynthesizer()
    private var sessionConfigured = false

    /// Pure state → cue mapping. Only the three "something happened" transitions speak;
    /// bookkeeping events (recordStart/recordCancel/disarmed) are silent.
    static func cue(for event: SwingDetector.Event) -> CueKind? {
        switch event {
        case .armed: .armed
        case .triggered: .recordingStarted
        case .captured: .swingCaptured
        case .recordStart, .recordCancel, .disarmed: nil
        }
    }

    /// The countdown word for a manual 3-2-1 tick.
    static func countdownWord(_ n: Int) -> String {
        switch n {
        case 3: "three"
        case 2: "two"
        case 1: "one"
        default: String(n)
        }
    }

    var audioEnabled: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.audioCuesDefaultsKey) == nil { return true }
        return defaults.bool(forKey: Self.audioCuesDefaultsKey)
    }

    // MARK: - Transitions

    func emit(_ kind: CueKind) {
        switch kind {
        case .armed: armed()
        case .recordingStarted: recordingStarted()
        case .swingCaptured: swingCaptured()
        }
    }

    /// You are set. A soft chime plus a one-word spoken confirmation, so a golfer heads-up
    /// over the ball knows they are armed without looking back at the phone.
    func armed() {
        guard audioEnabled else { return }
        ensureSession()
        chime(1113)          // "Begin Record" — a clean up-chime
        utter("Set")
    }

    /// Swing detected, recording. A short tone only — no speech, so nothing talks over the
    /// swing itself.
    func recordingStarted() {
        guard audioEnabled else { return }
        ensureSession()
        chime(1117)          // "Begin Video Record"
    }

    /// Swing captured. A success chime and a brief confirmation.
    func swingCaptured() {
        guard audioEnabled else { return }
        ensureSession()
        chime(1118)          // "End Video Record"
        utter("Got it")
    }

    /// Speak one countdown word. Called once per 3-2-1 tick from the manual countdown loop.
    func speak(_ text: String) {
        guard audioEnabled else { return }
        ensureSession()
        utter(text)
    }

    // MARK: - Plumbing

    private func utter(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0
        synth.speak(utterance)
    }

    private func chime(_ id: SystemSoundID) {
        AudioServicesPlaySystemSound(id)
    }

    /// Configure the shared audio session exactly once. `.ambient` respects the mute
    /// switch; `.mixWithOthers`/`.duckOthers` keep a golfer's music playing (ducked)
    /// rather than cutting it. Skipped in the Simulator, which has no real session.
    private func ensureSession() {
        guard !sessionConfigured else { return }
        sessionConfigured = true
        #if !targetEnvironment(simulator)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers, .duckOthers])
        try? session.setActive(true)
        #endif
    }
}
