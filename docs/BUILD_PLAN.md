# Swing Through — native build plan

The native SwiftUI app. The React mock in `reference/` is the visual spec; `docs/SWING_MODEL.md`
is the biomechanics spec; `docs/FABLE_PROMPT.md` is the product spec. This file records the
architecture and the *why* behind decisions so the thread survives long runs.

## Repo layout

```
project.yml          XcodeGen spec (tools/bin/xcodegen generate)
SwingThrough/        iOS app (SwiftUI) — UI, capture, avatar, store
SwingKit/            Swift package — the entire measurement pipeline (platform-agnostic)
swingctl/            macOS CLI over SwingKit — runs the pipeline on sample videos
reference/           the React prototype (visual spec, frozen)
samples/             real swing videos for validation (gitignored; samples/fetch.sh)
assets/fonts/        Instrument Serif + Satoshi (gitignored; assets/fetch_fonts.sh)
tools/               frames (AVFoundation frame dumper), bin/ (xcodegen, frames)
docs/                specs + decision log
```

## The two-layer architecture (non-negotiable, from the spec)

1. **Measurement (SwingKit, on-device):** AVFoundation reads the video →
   `VNDetectHumanBodyPose3DRequest` (17 joints, model space, camera transform) +
   `VNDetectHumanBodyPoseRequest` (2D, per-frame, for image-space overlays) → smoothing →
   checkpoint detection (P1–P10) → biomechanics *computed from geometry*: swing plane +
   deviation, kinematic sequence, 6-DOF pelvis/chest, tempo, turn/tilt/sway metrics →
   `SwingReport` (Codable). No ML guessing at biomechanics; math on joint tracks only.
2. **Interpretation (CoachingEngine):** structured `SwingReport` + swing model → Claude API
   → prioritized goals (current → target + drill). Rule-based fallback with the same output
   schema so the app works offline. Raw video never leaves the device.

**Why SwingKit is a package:** the identical pipeline compiles for macOS, so `swingctl` can
run it against `samples/*.mp4` on this Mac — that is the accuracy-validation loop (dump
JSON metrics + annotated overlay frames, eyeball against what the swing actually does).
The app and the validator can never drift apart.

## Verification loops (both are first-class)

- **Accuracy:** `swingctl analyze samples/dtl_iron_a.mp4 --dump-frames` → per-checkpoint
  overlay renders + metric JSON. Sanity-check: does detected P4 (top) frame *look* like the
  top? Is the plane line where the shaft is? Sequence order plausible? Documented in
  `docs/VALIDATION.md` as it happens.
- **UI:** boot iPhone 17 Pro sim (iOS 26.5) → `xcodebuild` install/launch → drive flows via
  XCUITest → `simctl io recordVideo` → `tools/bin/frames` dumps frames → PIL scripts diff/
  crop/zoom to catch hitches and misalignments. No ffmpeg on this Mac; `frames` replaces it.

## Key technical decisions

- **XcodeGen** (vendored binary in `tools/bin`, no brew) — project.yml regenerates
  `.xcodeproj` as files are added; no hand-editing pbxproj.
- **Club/shaft:** Vision body pose has no club joints. Plane math uses the grip (wrist
  midpoint) path; the address shaft line is estimated from the DTL silhouette (hands →
  ball line detected in the address frame). Attempt a lightweight image-space shaft-line
  detector at key checkpoints; if it's not robust, report hand-plane deviation only and
  say so honestly in the UI copy. Never fake a number.
- **Avatar:** SceneKit humanoid, sculptural + refined, driven directly by the 3D joint
  tracks (bones positioned per-frame, no retarget-to-rig complexity in v1). Plane disc and
  hand/club path arc as translucent geometry. Ghost = second instance, offset + translucent.
- **Fonts:** Instrument Serif (display) + Satoshi (UI) via fetch script (Fontshare files
  stay out of git for license hygiene).
- **Store:** SwiftData for swing history (report JSON + video URL + score), simple.
- **API key:** `ANTHROPIC_API_KEY` from process env (simctl launch --setenv for dev) or a
  user-provided key in Settings, stored in Keychain. Not compiled in. No key → rule-based
  coach, visibly labeled.
- **Stock samples are 25fps** — fine for angles/sequence validation; tempo resolution is
  ±40ms there. Device capture will request 60/120fps (`AVCaptureDevice` format selection).

## Phases

0. Toolchain + assets (xcodegen, fonts, samples, frames tool) ✅
1. Scaffold project + design system → running in Simulator
2. Measurement pipeline in SwingKit, validated via swingctl on samples ← the core
3. Analysis UI (Video / 3D / Split, scrubber, markers, metrics, score)
4. 3D avatar (SceneKit) from real tracks; plane disc; path arc; ghost compare
5. Capture (guides, live pose cues, auto-detect, countdown, two-angle fusion)
6. Coaching (Claude API + rule fallback) + Goals UI
7. History, drills, icon, polish; frame-level UI verification; VALIDATION.md

## Gotchas discovered (so nobody re-learns them)

- **SwiftUI `.frame(width:height:)` centers oversized children.** An inner view taller
  than the frame gets silently centered, adding a hidden offset — pass
  `alignment: .topLeading` (this cost us the first video-crop debugging round).
- **`colorEffect` blanks UIKit-backed views** (ScrollView, player layers). Grain goes on
  the canvas color layer only.
- **Derived data must live outside `~/Documents`** — iCloud fileprovider xattrs make
  codesign reject the bundle ("resource fork … not allowed"). All build scripts use
  `~/Library/Caches/*-dd`.
- **Never re-create a view hosting AVPlayerLayer** — re-attachment flashes blank.
  Panes resize one persistent player view instead of swapping instances.
- **XCUITest**: SwiftUI `Text` inside `Button` is exposed as the button's *label*, not a
  `staticText`; query `app.buttons[...]` or set accessibility identifiers. Never assert
  on date-relative labels ("Today") — they roll over at midnight mid-run.
- **simctl env vars** need the `SIMCTL_CHILD_` prefix; `recordVideo` writes VFR video —
  frame timestamps, not wall clock, are the truth.
- **Vision at 2.5K is slow (~150 ms/frame both requests)** — fast 2D pass runs
  downscaled, 3D only on the detected swing window.
