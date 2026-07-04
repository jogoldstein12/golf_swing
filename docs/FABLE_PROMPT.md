# The Master Fable Prompt — building Swing Through natively

This is the handoff artifact. You run it on **your Mac** with **Claude Code + Claude Fable 5
at `xhigh` effort**, in an **empty folder**, to build the real native iOS app. The web
prototype in this repo is the *visual and functional reference* — Fable should look at it,
not reverse-engineer it blind.

## Before you paste it
1. **Mac with Xcode command-line tools** (`xcodebuild`, `xcrun`, `simctl`). Fable drives
   these from the terminal — you do not need to open Xcode yourself. A **free Apple ID** is
   enough to run in the Simulator and on your own iPhone.
2. Put a **Claude API key** in a `.env` file in the project folder: `ANTHROPIC_API_KEY=…`
   (for the coaching layer). Fable will wire a tiny proxy so the key never ships in the app.
3. Have **one or two real swing videos** handy (down-the-line and face-on) as test input —
   accuracy work needs real footage to verify against. Drop them in a `samples/` folder.
4. Optional but recommended: **copy this repo's `docs/` folder** (SWING_MODEL.md,
   FEATURES.md) into the project so Fable has the full swing model and feature notes, and
   point it at the prototype for the look.
5. Install the **Satoshi** font files (Fontshare) into the project — it's the intended UI
   face and is trivial to add on device (the sandbox that built the prototype couldn't
   fetch it, so the prototype substitutes Hubot Sans).

## Notes on why it's shaped this way
- It leads with **intent and the accuracy architecture**, because that's the thing that
  makes or breaks this app — then leaves execution latitude, per Fable's prompting guidance.
- It sets up the **self-verification loop** from the calorie-tracker article (drive the
  simulator, dump frames with ffmpeg, pixel-diff, fix every hitch) — the single highest-
  leverage instruction for getting non-slop, Apple-quality output.
- It states **boundaries** and asks Fable to **scope and proceed autonomously**, only
  stopping when genuinely blocked.

---

## ===== BEGIN MASTER PROMPT (paste everything below) =====

I want you to build **Swing Through**, a professional golf-swing analysis app for iPhone.
Build it natively in SwiftUI, end to end. Work autonomously: scope it, make your own
judgment calls, and only stop to ask me if you hit something genuinely blocking. Use `xhigh`
effort. There is a web prototype at `./reference/` (React) — study it for the exact visual
language, layout, and feature behavior. It is a faithful mock; your job is to make it real
and native, and better.

### What matters most (read this twice)
Two things determine whether this app is good, and I care about them more than feature count:

1. **The analysis must be genuinely accurate, and the feedback detailed and specific** —
   never generic "you're coming over the top, fix it" fluff. The way you achieve this is a
   strict two-layer architecture, and you must not shortcut it:
   - **Measurement layer (hard numbers):** Use Apple's Vision framework on-device
     (`VNDetectHumanBodyPose3DRequest` / body-pose requests, plus CoreMotion where useful)
     to extract per-frame **3D joint tracks** from the swing video. From those tracks,
     *compute* the biomechanics yourself — swing-plane angle and deviation, the kinematic
     sequence, the six degrees of freedom (turn/bend/side-bend/sway/lift/thrust for pelvis
     and chest), tempo, and auto-detect the swing checkpoints P1–P10. These are math on the
     joint positions, not guesses.
   - **Interpretation layer (coaching):** Send the *computed numbers* plus the swing model
     (below) to Claude via the API to generate the detailed, prioritized coaching notes and
     drills. **Never send raw video or frames to the model to "eyeball" the swing** — vision
     models are unreliable at precise form measurement. Numbers come from Vision; words come
     from Claude, grounded in the numbers.
   Validate accuracy against the real sample swing videos in `./samples/`. Build guided
   **camera-setup** requirements (framing, distance, lighting, plain background, frame rate)
   because accuracy depends on them.

2. **It must look like the top 1% of human design — instantly eligible for an Apple Design
   Award — and contain zero AI-slop tells.** No emoji icons, no stock SF Symbols where a
   custom mark is better, no generic gradients, no default system fonts, no awkward spacing,
   no janky transitions. Write custom SwiftUI components and Metal shaders where they make
   things feel special. Sweat every pixel and every frame of every animation.

### The design system (match the prototype exactly, then elevate)
- **Canvas:** warm bone white `#F5F3EE` (never pure white). Cards float on `#FCFBF8` with
  soft, diffused ambient shadows — a light, airy, "non-uniform glass" feel, not hard frost.
- **Ink:** warm near-black `#191712` (never pure black), used at 100/70/45/25/8% opacities.
- **Signature accent:** a single "fairway" chartreuse-green `#B4E019` (deep `#8FB80F`). Use
  it on **under 5% of any screen** — only for live/active measurement and the primary action.
  A warm brick red `#CE4A2C` marks faults, a warm amber `#DB851F` marks off-plane. Never
  decorate with color.
- **Type:** **Instrument Serif** for the wordmark, hero numerals, and editorial pull-quotes;
  **Satoshi** for all UI and technical readouts. This pairing is deliberate — do not
  substitute Inter, SF, or Geist (those read as AI-default).
- **Layout:** editorial magazine, not dashboard. Generous margins, asymmetric grid, one
  dominant element per screen, hairline dividers, tiny uppercase letter-spaced micro-labels,
  big thin numerals beside small labels.
- **Motion:** spring-based, physical, buttery. Shared-element transitions between the swing
  thumbnail and the analysis hero, and between Video/3D/Split. Every transition must be
  flawless frame-to-frame.

### The 3D avatar
Render the swing as a highly detailed, photorealistic 3D Avatar with human features
on soft contact shadows — gallery-like, an instrument, not a video-game character. Use
SceneKit or RealityKit. It must **animate through the swing** driven by the real 3D joint
tracks, with a scrubbable timeline and jump-to-checkpoint (Address/Top/Impact/Follow, full
P1–P10 underneath). Show the translucent **swing-plane** disc and the **clubhead-path** arc.
Support overlaying **two swings** (or you vs. a reference) to compare — offset and ghost the
second. If you can achieve a Gaussian-splat / point-cloud aesthetic (à la MetalSplatter) as
an optional richer look, explore it, but the clay mannequin is the baseline.

### Core features (v1)
- **Capture:** record a swing with the phone. On-screen **framing/alignment guides** for the
  two canonical angles — **down-the-line** and **face-on** — plus auto swing-detection (no
  "press record" needed, like Sparrow) and a countdown. Support recording the two angles as
  separate swings and **fusing them into one report**. Give **real-time cues** during setup/
  capture using the live on-device pose (e.g., posture, alignment).
- **Analysis screen** with a **Video / 3D / Split** toggle (like Sportsbox). 
  - **Video:** the user's actual footage with the analysis overlaid — the tracked skeleton,
    the base **swing-plane line**, and the club shown **on-plane / over-the-top / under-plane**
    with a magnitude (e.g., "+4.2° steep at P5"), plus **contact points** and **tappable
    green (good) / red (fault) markers** on the body that expand to a detail note (like
    Sparrow's clickable circles).
  - **3D:** the animated clay avatar. **Split:** both together.
  - A **checkpoint scrubber** (Address/Top/Impact/Follow) that drives all views in sync.
- **Metrics** shown against their **ideal bands** (swing plane, tempo, shoulder turn, hip
  turn, spine angle, sway…), each derived from the tracks.
- **Swing Score** (0–100) computed from the swing model, weighted toward sequence and plane.
- **Goals:** the coaching output as a short, **priority-ordered** list — fix the earliest
  link in the chain first (sequence/plane before cosmetics). Each goal has a **current →
  target** metric and a **drill**.
- **History:** a swing gallery with the score trending over time; a **drill library** keyed
  to the user's detected faults; optional pro-comparison.

### The swing model (ground all analysis and coaching in this)
- **Kinematic sequence** is the backbone: an efficient downswing unloads ground-up —
  **pelvis → torso → lead arm → club**, each peaking after its driver. Arms/club firing
  early (casting/over-the-top) or no pelvis-torso separation are the core faults. Measure
  the peak-speed order and transition sequence.
- **Swing plane (down-the-line):** base plane = ball through the hands/shaft at address,
  extended. **Over the top** = club works above/outside the plane in transition, out-to-in,
  causes pulls/slices. **Under plane** = club drops below, in-to-out, causes blocks/hooks.
  Detect, overlay, and report with a degree magnitude.
- **Six degrees of freedom** (pelvis & chest, referenced to address): turn (~90° shoulders /
  ~45° hips at top), bend (hold spine tilt — early extension is a fault), side-bend, sway
  (small, centered pivot), lift/drop, thrust (stable — thrust toward the ball = early
  extension). Report in degrees and inches.
- **Checkpoints:** P1 address, P2 takeaway, P3 lead-arm-parallel, P4 top, P5 transition,
  P6 delivery, P7 impact, P8–P10 follow/finish. Auto-detect from the motion.
- **Tempo:** backswing:downswing time ratio, tour benchmark ~3:1.
- **Coaching principle:** always prioritize fixing the earliest fault in the chain; be
  specific and quantified; prescribe a concrete drill per goal. (Full detail is in
  `./docs/SWING_MODEL.md` if present — read it.)

### Engineering
- SwiftUI, targeting current iOS. On-device Vision + CoreMotion for pose; AVFoundation for
  capture; SceneKit/RealityKit + Metal for the 3D avatar and any shaders; SwiftData (or
  simple local store) for history. Everything runs on-device except the coaching text.
- **Coaching via Claude API:** read `ANTHROPIC_API_KEY` from the environment / a local
  config; do not embed it in the app binary. Design the request so the model receives the
  structured metrics + swing model and returns structured coaching (goals, notes, drills).
  Handle the network being unavailable gracefully (fall back to a rule-based version so the
  app still works offline).
- Keep the code clean, modular, and documented. Drive all builds and the Simulator from the
  CLI (`xcodebuild`, `xcrun simctl`); you do not need to open Xcode.

### How to verify your work (do not skip this — it's the point)
I want a flawless, hitch-free, premium interface, and you must actually verify it, not
assume it. Set up a loop to check your own work:
- Build and run in the Simulator from the CLI. Drive it (taps, swipes, scrubbing) and
  **record the screen with ffmpeg, dump frames, and inspect them** — write small scripts to
  diff frames, crop, and zoom so you can catch pops, hitches, misalignments, and jank in
  transitions. Fix them until every transition is smooth frame-to-frame and every screen is
  pixel-clean. Aim for something Alan Dye would ship.
- **Verify the analysis, not just the looks:** run your pose→biomechanics pipeline on the
  real sample videos and sanity-check the numbers (plane angle, sequence order, checkpoint
  timings) against what the swing actually does. If a number is wrong, the coaching built on
  it is worse than useless — treat measurement correctness as a first-class test.
- Use fresh-context checks periodically: re-verify the build, the key flows, and the numbers
  against this spec as you go.

### Delegation and verification (use subagents)
You dispatch subagents well — use them, and delegate freely while you keep working. Two
patterns matter most here:
- **Fresh-context verifiers (highest value).** After you finish a screen or the analysis
  pipeline, spin up a subagent with fresh context to check it against this spec — separate
  eyes catch what self-review misses. Run two kinds: an **aesthetics** verifier that drives
  the Simulator, dumps frames, and hunts for slop, jank, misalignment, and hitched
  transitions; and an **analysis-correctness** verifier that runs the pose→biomechanics
  pipeline on the sample videos and confirms the plane angles, sequence order, checkpoint
  timings, and 6-DOF numbers are actually right. Treat a failed verification as a bug to fix,
  not a note to file.
- **Parallel independent modules.** The capture flow, the biomechanics engine, the 3D
  avatar/animation, and the design-system components are largely independent — build them in
  parallel with subagents and integrate, rather than strictly serially. Keep a long-lived
  subagent on a module so it retains context across its subtasks.
Step in if a subagent drifts off-spec or is missing context. Don't over-formalize this into a
rigid pipeline — delegate where it genuinely helps and stay in the loop.

### Working style
- Initialize git immediately and commit as you go. Keep a `docs/` with your intent and
  decisions so you don't lose the thread across long runs. Document *why*, not just *what*.
- Build the whole thing end to end. Don't over-engineer or add scope I didn't ask for; do
  the simplest thing that's genuinely excellent. Don't add abstractions or fallbacks for
  cases that can't happen.
- Before reporting progress, check claims against real build/test results — if something
  isn't verified, say so. Proceed autonomously on reversible steps; only pause for me on a
  real blocker (a missing credential, a decision only I can make).
- Use the web freely to pull docs, SDK references, and resources. Don't settle for boring
  iOS defaults — dig deep and make it feel special. Have fun with it.

Start by initializing git and scaffolding the project, sketch a short build plan in
`docs/`, then build. Show me a running app in the Simulator as early as you can, then
iterate on both accuracy and aesthetics until it's genuinely award-quality.

## ===== END MASTER PROMPT =====

---

## A good follow-up prompt (after the first build, to push the design — from the article)
> This is a strong start, but I want you to 100× the design and prove it's not AI-generated.
> Get every pixel perfect and every transition flawless frame-to-frame. Audit frames with
> ffmpeg and pixel-diff scripts, and don't stop until it looks like the top 1% of human
> designers — instantly eligible for an Apple Design Award. Write custom components and Metal
> shaders wherever it helps. Then do the same rigor on the *analysis*: verify the plane
> angles, sequence, and checkpoint detection against the sample videos frame by frame.

## Open items to confirm before/while running
- **Satoshi font** installed in the project (intended UI face).
- **`ANTHROPIC_API_KEY`** available for the coaching layer.
- **Sample swing videos** (down-the-line + face-on) in `./samples/` to verify accuracy.
- **v1 scope**: capture + analysis + goals + history is the recommended first cut; pro-
  comparison and the full drill library can follow.
