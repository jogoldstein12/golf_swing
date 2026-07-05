# Swing Through

A professional golf-swing analysis app for iPhone, built natively in SwiftUI. Record a
swing, and Swing Through measures it on-device — 3D joint tracks from Apple's Vision
framework, turned into hard biomechanics by geometry (never by a model's guess) — then
coaches you through what it found, in priority order, grounded in those numbers.

**The two-layer rule that defines the app:**

1. **Measurement (on-device, SwingKit).** Video → Vision 3D+2D body pose → smoothing →
   auto-detected P1–P10 checkpoints → swing plane + signed deviation, kinematic sequence,
   six degrees of freedom for pelvis & chest, tempo, turn/posture metrics → a `SwingReport`.
   Every number is math on joint positions. When something can't be measured (shaft not
   visible, orientation confidence low), the report says so instead of inventing it.
2. **Interpretation (words, not measurements).** Deterministic coaching renders with
   the local results first. If configured, the compact structured report then goes to
   Claude (`claude-opus-4-8`) for optional enhanced coaching — prioritized by the swing
   model's chain: sequence and plane before posture, posture before tempo, tempo before
   cosmetics. No key or no network? A deterministic rule-based coach applies the same
   model with the same priorities. Raw video never leaves the phone.

## What's in the app

- **Capture** — framing guides for down-the-line and face-on, a live setup checklist
  (full body / distance / phone upright / light) computed from on-device pose, and auto
  swing detection: hold still to arm, swing, and the clip is captured with pre-roll and
  takeaway-aware trim. Manual record with a serif 3-2-1 countdown as fallback.
- **Analysis** — your footage with the measured skeleton, base plane line, on-plane /
  over-the-top / under-plane state with degree callouts (e.g. `+4.2°` at P5), contact
  points, and tappable good/fault markers that expand into specific notes. **Video / 3D /
  Split** panes share one timeline: headline checkpoints (Address · Top · Impact ·
  Follow), a full P1–P10 tick timeline with drag scrubbing, and playback.
- **3D avatar** — a sculpted clay mannequin animated by your actual joint tracks, with
  swing-plane disc and downswing path ribbon, orbit/pinch, and a ghost-compare mode.
- **Metrics & score** — each metric includes measurement provenance and is shown against
  its ideal band. The 0–100 Swing Score appears only when pose/checkpoint coverage is
  sufficient and uses view-appropriate components (face-on swings are not penalized for
  missing down-the-line plane data).
- **Goals** — 2–4 coaching goals in priority order, each with current → target and a
  concrete drill.
- **History & drills** — swing gallery with score trend; a drill library where the
  drills prescribed for *your* faults lead.

## Repo layout

```
project.yml          XcodeGen project spec (tools/bin/xcodegen/bin/xcodegen generate)
SwingThrough/        iOS app — screens, capture, avatar, store, design system
SwingKit/            Swift package — the entire measurement + coaching engine
  Sources/swingctl/  macOS CLI over the same pipeline (the accuracy-validation loop)
SwingThroughUITests/ scripted drive tests for recorded frame-level UI verification
reference/           the original React design prototype (frozen visual spec)
samples/             real swing footage for validation (gitignored → samples/fetch.sh)
assets/              fonts (gitignored → assets/fetch_fonts.sh), app-font subset
tools/               frames (AVFoundation frame dumper), render_icon.py, vendored xcodegen
docs/                SWING_MODEL.md · BUILD_PLAN.md · VALIDATION.md · DESIGN.md · …
```

## Build & run

Prereqs: macOS with Xcode 26+ and network access for first-run dependency fetches. No
brew, ffmpeg, CocoaPods, or remote Swift packages are required.

```sh
./tools/bootstrap_xcodegen.sh     # pinned XcodeGen 2.45.4 (first clone only)
./assets/fetch_fonts.sh          # Instrument Serif + Satoshi (kept out of git)
./samples/fetch.sh               # real swing clips for validation (optional but recommended)
tools/bin/xcodegen/bin/xcodegen generate

# Build + run in the Simulator (derived data must live OUTSIDE ~/Documents — iCloud
# xattrs break codesign; see docs/BUILD_PLAN.md gotchas):
DD=~/Library/Caches/swingthrough-dd
xcodebuild -project SwingThrough.xcodeproj -scheme SwingThrough \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath "$DD" build
xcrun simctl install booted "$DD/Build/Products/Debug-iphonesimulator/SwingThrough.app"
xcrun simctl launch booted com.swingthrough.SwingThrough
```

Run the complete local build and package-test sequence with `./tools/verify.sh`. Override
`SWINGTHROUGH_DESTINATION` or `SWINGTHROUGH_DERIVED_DATA` when needed.

Imported videos are preflighted locally, previewed, and trimmed to a maximum 15-second
analysis range before work starts. Coarse Vision is capped at 12 fps/720 px and detailed
2D+3D work at 30 fps/960 px regardless of source FPS; the original remains intact for
playback. The Simulator can't run Vision or the camera, so the app ships with a pre-analyzed
sample swing (gallery → "Sample") that exercises every surface. On a device, capture
and the full measurement pipeline run for real.

**Dev routing** (screenshot/verification hooks, via `SIMCTL_CHILD_` env on launch):
`ST_SCREEN=avatar|capture|analysis|settings|drills|analyzing`, `ST_POS=p1…p10`,
`ST_PANE=avatar|split`, `ST_SCROLL=metrics|bottom`, `ST_FEED=file` (capture from the
bundled clip), `ST_RUN_SAMPLE=1` (device-only end-to-end run of the sample).

### The validation CLI

The identical pipeline compiles for macOS, so measurements are validated against real
footage without a device:

```sh
cd SwingKit && swift build -c release && swift test
.build/release/swingctl analyze ../samples/dtl_iron_a.mp4 --view dtl \
    --json /tmp/report.json --diagnostics /tmp/diagnostics.json \
    --annotate /tmp/frames                             # skeleton+plane burned onto checkpoint frames
.build/release/swingctl coach /tmp/report.json          # rule-based coaching
.build/release/swingctl coach /tmp/report.json --claude # via API (needs ANTHROPIC_API_KEY)
```

`docs/VALIDATION.md` records the measured numbers per sample clip and the honest visual
assessment of each detected checkpoint. Treat it as the acceptance test for the
measurement layer.

### Claude coaching key

Never compiled in. Either export `ANTHROPIC_API_KEY` (CLI / `SIMCTL_CHILD_ANTHROPIC_API_KEY`
for the sim), or add a key in the app's Settings (stored in the Keychain, deletable).
Only the compact measured-numbers payload is sent; never video or frames. Enhanced
coaching runs after local results are visible, uses a single short attempt, and safely
keeps local coaching on timeout, cancellation, malformed output, or rate limiting.

### Local data and privacy

Videos, reports, job manifests, diagnostics, and API credentials stay in app-owned local
storage. Cancelled/interrupted analyses retain their source for explicit retry or discard.
Long-press a history row to correct club/angle or delete that swing; Settings includes a
confirmed “Delete all local swing data” action. Debug diagnostics contain timings and
stable categories, never media, pose coordinates, coaching text, or file paths.

## Design language

Editorial golf lab: warm bone canvas (`#F5F3EE`), paper cards with soft float shadows,
warm near-black ink at stepped opacities, and a single rationed fairway accent
(`#B4E019` / `#8FB80F`) reserved for live measurement and the primary action. Brick red
marks faults, amber marks off-plane. Type is Instrument Serif (wordmark, hero numerals,
pull-quotes) and Satoshi (all UI) — deliberately not Inter/SF. Custom-drawn glyphs
throughout; no SF Symbols in primary chrome, no emoji. Motion is spring-based and
verified frame-by-frame from screen recordings (see `SwingThroughUITests/DriveTests`).

## Honest limitations (current build)

- **Simulator**: Vision body-pose cannot initialize there — capture dev-mode uses the
  fixture's precomputed tracks; the end-to-end pipeline needs a device or `swingctl`.
- **Sample footage is 25fps**, so validation tempo/impact timing carries ±40ms
  quantization (the capture path targets 60fps on device, not yet field-tested).
- **No club tracking yet** — plane math anchors on the grip (wrist midpoint) path and a
  shaft line detected in the address frame; deviations are grip-path deviations.
- **Kinematic-sequence order and total score are confidence-gated**: when coverage or
  body orientation is inadequate, unavailable components are omitted and the app shows
  a clear limited-data state instead of neutral-filled precision.
- Real-device testing (camera formats, thresholds against live golfers, thermal/perf)
  hasn't happened yet — everything device-side is structured but sim/CLI-verified only.

## To be built (roadmap)

**Near-term (v1.1)**
- Two-angle fusion UI: record DTL + face-on and merge into one report
  (`SwingReport.fused` exists in SwingKit; needs the flow + gallery pairing UX).
- Kinematic-sequence graph on the analysis screen (the per-segment angular-velocity
  series is already in every report).
- Real-device field pass: verify the fixed 1080p60-class capture profile, detector
  thresholds against live swings, battery/thermal behavior, and capture haptics.
- Onboarding: first-run camera-setup walkthrough (height, distance, angle) with the
  live checklist.
- Share/export: a designed swing card (score, plane callout, one goal) as an image.

**Mid-term**
- Club/shaft tracking at high frame rates (line detection through the downswing) for
  true shaft-plane deviation and club speed; contact-quality inference.
- Pro-comparison mode: bundled reference swings, ghost-overlaid and checkpoint-synced
  on both video and 3D (GhostTrack API is already in the avatar).
- Per-club history, filters, and trend analytics; goal streaks and "fixed" detection
  (fault disappears across N swings).
- Claude coaching continuity: session memory of prior goals (context field exists),
  progression narratives, drill follow-ups.
- Face-on-specific measurements: sway/weight-shift emphasis, head stability box.

**Exploratory**
- Gaussian-splat / point-cloud avatar aesthetic (MetalSplatter-style) as an optional
  richer look over the clay mannequin.
- Apple Watch as remote trigger + wrist tempo sensor (CoreMotion fusion).
- iPad landscape review layout; AirPlay/external display for coaching sessions.
- Localization; VoiceOver audit beyond the current identifier coverage.
- On-device coaching with a local model as a third fallback tier.
