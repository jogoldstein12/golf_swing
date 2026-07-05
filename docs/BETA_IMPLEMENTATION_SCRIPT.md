# SwingThrough MVP-to-Beta Implementation Script

This document is an execution brief for a coding agent working in this repository. It
turns the current MVP into a measurable, recoverable, confidence-aware beta. Execute it
phase by phase. Do not combine all phases into one unreviewable change.

## Role and objective

You are working in the local Xcode/iOS repository for SwingThrough, an on-device golf
swing analysis app. Preserve its current editorial design language and its core product
rule:

1. SwingKit measures joint tracks and biomechanics from video.
2. Coaching interprets measured values but never invents measurements.

The beta must analyze ordinary five-second swing videos reliably, avoid memory-pressure
termination, show useful results before network coaching completes, recover from
interruption, and clearly communicate measurement confidence.

## Non-negotiable constraints

- Do not rewrite the application wholesale.
- Keep raw video on-device unless the user explicitly opts into a future cloud feature.
- Never place AI-generated values into the measurement layer.
- Preserve the original imported video for playback; use lower-resolution buffers or a
  proxy only for analysis.
- Never process 60- or 120-fps footage at native FPS merely because it was recorded that
  way.
- Never block deterministic results on remote coaching.
- Do not show a precise Swing Score when measurement coverage is inadequate.
- Add cancellation checks inside every long-running loop.
- Make each phase independently buildable, testable, and revertible.
- Preserve unrelated worktree changes.
- Use `apply_patch` for source edits and XcodeGen for project regeneration.

## Baseline findings to treat as verified

- `SwingAnalyzer` currently performs a whole-video 2D pass and then a detailed 2D+3D
  pass.
- Both passes default to native FPS because `PoseExtractor.Options.sampleFPS` is nil.
- Five seconds at 60 fps can therefore produce roughly 300 coarse Vision operations and
  300 combined 2D/3D operations. At 120 fps, that doubles.
- `PoseExtractor` allocates Vision requests and downscaled pixel buffers per frame, does
  not use a per-frame autorelease pool, and aborts the entire run on a single Vision
  error.
- `SwingSession` schedules a main-actor task for every progress callback.
- Claude coaching uses a 15-second timeout and one retry, potentially adding about 30.5
  seconds before results appear.
- Import copies a Photos-owned file to temporary storage, then persistence copies it
  again.
- Imported videos are always labeled down-the-line and all swings are currently labeled
  `7 Iron`.
- Missing measurements are scored as neutral 0.5 components, which can make incomplete
  analysis look authoritative.
- SceneKit renders continuously even while its pane is hidden, and both SceneKit and
  AVPlayer attempt to advance the playback timeline.
- The repository has strong math-level tests but no app unit-test target, no analysis
  performance suite, and no real-device beta telemetry.
- `README.md` references `docs/VALIDATION.md`, but that validation document is absent.

## Beta service-level objectives

Measure these on supported real iPhones; do not claim them from Simulator results.

- Five-second 1080p60 local video: first deterministic results under 15 seconds median
  and under 25 seconds p95.
- Crash-free analysis sessions above 99.5%.
- Valid, properly framed swing analysis success above 90%.
- Cancel acknowledgement under one second.
- Progress UI updates no more than 5–10 times per second.
- Invalid or unsupported video rejected during preflight, before expensive 3D work.
- Interrupted jobs remain retryable; the selected video is not silently deleted.
- Remote coaching never delays first results.

## Execution protocol for every phase

1. Inspect the current branch and worktree before editing.
2. Record baseline behavior relevant to the phase.
3. Implement the smallest coherent change.
4. Add focused tests before moving to the next phase.
5. Regenerate the project when targets or files change:

   ```sh
   tools/bin/xcodegen/bin/xcodegen generate
   ```

6. Run the available checks:

   ```sh
   DD="$HOME/Library/Caches/swingthrough-dd"
   xcodebuild -project SwingThrough.xcodeproj -scheme SwingThrough \
     -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
     -derivedDataPath "$DD" build

   cd SwingKit && swift test
   ```

7. For device-only work, record device model, OS, input duration/resolution/FPS, stage
   timings, peak memory, thermal state, result, and failure reason.
8. Do not proceed through a failed acceptance gate by weakening the test.

---

## Phase 0 — Instrument before optimizing

### Goal

Make every analysis run explain where time and failures occur. This phase must land before
performance changes so improvements can be compared against a baseline.

### Implementation

Add a diagnostics type in SwingKit, for example:

```swift
public struct AnalysisDiagnostics: Codable, Sendable {
    public var jobID: UUID
    public var sourceDuration: Double
    public var sourceFPS: Double
    public var sourceWidth: Int
    public var sourceHeight: Int
    public var sampled2DFrames: Int
    public var sampled3DFrames: Int
    public var droppedFrames: Int
    public var recoverableFrameErrors: Int
    public var stageDurations: [String: Double]
    public var peakMemoryBytes: UInt64?
    public var thermalStates: [String]
}
```

- Add `OSLog` signposts around preflight, preparation, coarse pose, detailed pose,
  checkpoints, plane, metrics, persistence, local coaching, and remote coaching.
- Give every run a UUID and include it in structured logs.
- Log only metadata and error categories; never log video, joint coordinates, API keys,
  coaching text, or personally identifying paths.
- Capture `ProcessInfo.processInfo.thermalState` at stage boundaries.
- Add a MetricKit subscriber in the app for crash, hang, CPU, and memory diagnostics.
- Add a debug-only diagnostics screen or JSON export so device testers can share one run
  without exposing the video.
- Throttle progress publication to at most 10 Hz.

### Likely files

- `SwingKit/Sources/SwingKit/Pipeline/SwingAnalyzer.swift`
- `SwingKit/Sources/SwingKit/Pipeline/PoseExtractor.swift`
- `SwingThrough/Screens/Analyze/SwingSession.swift`
- New `SwingThrough/Diagnostics/MetricKitMonitor.swift`
- New `SwingKit/Sources/SwingKit/Pipeline/AnalysisDiagnostics.swift`

### Tests and gate

- Unit-test duration aggregation and redaction.
- Verify a failed run still closes every signpost interval.
- Verify progress callbacks are throttled.
- On a device, produce a stage timing report for bundled and imported samples.

Do not optimize until at least three real-device baseline runs exist.

---

## Phase 1 — Introduce a cancellable, persistent analysis job

### Goal

Replace the monolithic `SwingSession.run` flow with an explicit job state machine while
keeping the existing UI operational.

### Target state model

```swift
enum AnalysisStage: String, Codable, Sendable {
    case queued
    case preparing
    case detectingSwing
    case tracking2D
    case tracking3D
    case measuring
    case resultsReady
    case enhancingCoaching
    case saving
    case completed
    case failed
    case cancelled
}

struct AnalysisProgress: Sendable {
    var jobID: UUID
    var stage: AnalysisStage
    var fraction: Double
    var message: String
    var estimatedSecondsRemaining: Double?
}
```

- Create an `AnalysisJobCoordinator` actor that owns the active task and enforces one
  foreground job at a time.
- Keep SwiftData `ModelContext` access on the main actor. Pass Sendable value types between
  the coordinator and persistence layer.
- Add `Task.checkCancellation()` before each stage and inside every frame loop.
- Store the imported/captured video before analysis starts.
- Persist job ID, stage, input metadata, file name, attempt count, and last error.
- Keep failed inputs for retry. Delete only when the user deletes or explicitly discards
  the job.
- Cancel the task when requested, but do not destroy its source video automatically.
- Protect state updates with job IDs so late progress cannot overwrite a later failed or
  cancelled state.
- Add a visible Cancel action on the analysis screen.
- When the app launches, show interrupted jobs as retryable drafts.

### Architecture boundaries

Create protocols so the orchestration can be tested without Vision or disk:

```swift
protocol SwingAnalyzing: Sendable { /* analyze prepared input */ }
protocol SwingPersisting: Sendable { /* job/report/video persistence */ }
protocol SwingCoaching: Sendable { /* local and enhanced coaching */ }
```

Do not hide mutable camera or AVFoundation objects behind new `@unchecked Sendable`
conformances. Use actors, locks, immutable snapshots, or explicit queue confinement.

### Tests and gate

- Cancellation during every stage.
- Late progress cannot resurrect a failed job.
- A second job cannot silently replace the first.
- Relaunch exposes an interrupted job and retry uses the retained video.
- Persistence failure produces a recoverable error without orphaning the UI.

---

## Phase 2 — Add video preflight, setup, trimming, and preparation

### Goal

Reject bad work early and collect the context required for correct measurements.

### Preflight service

Create `VideoPreflightService` that loads:

- Duration.
- Nominal FPS.
- Display dimensions after preferred transform.
- Codec and pixel format where available.
- HDR/wide-color status.
- Whether a local Photos transfer has completed.
- Whether the video track is readable.

Return typed errors such as:

```swift
enum VideoPreflightError: LocalizedError {
    case noVideoTrack
    case tooShort
    case tooLong
    case unsupportedCodec
    case unreadable
    case invalidDimensions
}
```

### Import setup UI

After selecting a video, present a setup screen before analysis:

- Trim start and end, with a recommended maximum of 15 seconds.
- Down-the-line or face-on.
- Club selection; remember the last choice.
- Handedness selection with an `Auto` option and later override.
- Optional skill level, shot intent, and miss pattern for coaching only.
- Preview and explicit `Analyze swing` action.

Do not hard-code `.downTheLine` or `7 Iron` in `RootView`.

### Preparation

- Preserve the original video for playback.
- Analyze a bounded proxy or bounded decoded buffers, not 4K/HDR source frames.
- Prefer a maximum analysis dimension around 720–960 pixels; determine the final value
  by accuracy benchmarks.
- Normalize unsupported HDR/codec combinations only when required.
- Show separate download, preparation, and analysis progress. Never call a local copy an
  upload.
- Move prepared files into final app storage instead of copying the same bytes repeatedly.

### Tests and gate

- Local HEVC, H.264, HDR, portrait, landscape, 30/60/120 fps, and slow-motion inputs.
- iCloud-backed item progress and cancellation.
- Too-short, too-long, audio-only, damaged, and no-track files.
- Setup selections reach `SwingReport` and gallery metadata correctly.

---

## Phase 3 — Bound and restructure Vision work

### Goal

Make work proportional to useful swing information rather than source FPS.

### Recommended pipeline

1. Metadata preflight.
2. Coarse 2D pose at 10–15 fps and reduced resolution over the bounded clip.
3. Detect a swing window with a small margin.
4. Detailed 2D pose at about 30 fps inside that window.
5. 3D pose at 15–30 fps, or in neighborhoods around required checkpoints.
6. Interpolate or align 3D samples onto the 2D timeline.
7. Compute checkpoints and metrics.
8. Decode only the few still images needed by plane/ball analysis.

Treat these rates as initial budgets, not permanent truth. Accuracy benchmarks decide the
lowest acceptable sampling rate.

### PoseExtractor changes

- Add explicit `sample2DFPS`, `sample3DFPS`, and maximum analysis dimensions.
- Do not report source nominal FPS as the sampled track FPS.
- Use one stable timestamp contract across coarse, detailed, and interpolated tracks.
- Reuse Vision request objects when supported and safe.
- Evaluate `VNSequenceRequestHandler` for ordered video frames.
- Use a `CVPixelBufferPool` or decoder-side sizing instead of allocating a new full
  downscaled buffer for every frame.
- Put per-frame Objective-C/Vision work inside an autorelease pool.
- Catch individual frame failures. Continue within a defined error budget, such as no
  more than five consecutive failures and no more than 10% failed sampled frames.
- Throw a typed analysis error only when the quality budget is exceeded.
- Check cancellation before decode, Vision execution, result conversion, and append.
- Reuse live 2D pose tracks from in-app capture as the coarse pass when timestamps and
  orientation match the saved video.
- Stop early when coarse tracking proves that no full golfer or swing exists.

### Accuracy protection

- Compare old and new checkpoint times and metrics on every validation fixture.
- Establish tolerances per metric rather than requiring byte-identical reports.
- Keep a debug option for the old pipeline until the new pipeline is validated.
- Never silently interpolate across long 3D gaps; lower confidence instead.

### Tests and gate

- Assert an upper bound on Vision request count for 30/60/120-fps inputs.
- Verify cancellation releases the reader and temporary buffers.
- Fault-inject intermittent frame failures.
- Measure peak resident memory and stage duration on at least two real iPhone classes.
- New metrics remain within documented tolerances on the validation set.

---

## Phase 4 — Make reports confidence-aware

### Goal

Distinguish measured, estimated, and unavailable values and prevent misleading scores.

### Data model

Add report-level quality and per-metric provenance, for example:

```swift
public enum MeasurementProvenance: String, Codable, Sendable {
    case measured
    case interpolated
    case inferred
    case unavailable
}

public struct MeasurementQuality: Codable, Sendable {
    public var confidence: Double
    public var coverage: Double
    public var provenance: MeasurementProvenance
    public var warnings: [String]
}
```

- Add overall 2D coverage, 3D coverage, checkpoint confidence, plane basis, orientation
  confidence, and quality warnings to `SwingReport`.
- Version report JSON and SwiftData schema before beta data is distributed.
- Provide migrations and decode defaults for existing sample/reports.
- Make score availability explicit. Prefer an optional score or an `insufficientData`
  state over neutral-filling missing components.
- Set a documented coverage threshold before showing a total score.
- Display why a metric is unavailable and how to improve capture.
- Rename grip proxies honestly. Do not label grip speed as measured clubhead speed or a
  grip-path deviation as direct club tracking.
- Clearly mark the bundled provisional sample as illustrative until generated by the
  production pipeline.

### Contextual scoring

- Separate DTL, face-on, and fused score component definitions.
- Do not penalize a face-on swing for missing DTL plane data.
- Introduce club-specific bands only after collecting defensible validation data.
- Treat skill level, mobility, and shot intent as coaching context, not permission to
  fabricate different measurements.

### Tests and gate

- Low-coverage reports cannot show an authoritative score.
- Face-on reports do not include DTL-only components.
- Legacy reports decode and display safely.
- Every displayed metric has quality/provenance metadata.

---

## Phase 5 — Return results before enhanced coaching

### Goal

Make network coaching optional and asynchronous.

### Flow

1. Finish deterministic measurements.
2. Generate rule-based coaching locally.
3. Persist and show results immediately.
4. Start enhanced coaching as a separate cancellable job.
5. Replace or augment the coaching card when the response succeeds.
6. Keep local coaching when the request fails.

### Remote coaching changes

- Use one short timeout and avoid automatic retries on the foreground path.
- Respect task cancellation; do not swallow cancellation during retry sleep.
- Reduce maximum output tokens to the amount required for 2–4 concise goals.
- Make the model identifier configurable and validate unsupported-model errors.
- For a public beta, do not require ordinary users to bring their own provider API key.
  Prefer rule-based coaching by default and design a server-mediated, rate-limited,
  privacy-reviewed enhanced service separately.
- Show `Local coaching` or `Enhanced coaching` in a quiet, understandable way.

### Tests and gate

- Results render while remote coaching is offline, slow, malformed, cancelled, or rate
  limited.
- Remote completion updates only its matching swing.
- No raw frames or video fields enter the payload.

---

## Phase 6 — Remove results-screen lag and battery waste

### Goal

Keep video, overlays, scrubber, and avatar smooth without continuous hidden work.

### Changes

- Replace linear `SwingReport.frame(at:)` lookup with binary search or a cached index.
- Precompute smoothed framing-window values once instead of filtering all frames at 60
  Hz.
- Make AVPlayer the single playback clock. SceneKit consumes the model time but does not
  independently advance it.
- Disable continuous SceneKit rendering while paused or hidden.
- Lazily initialize the avatar when the user first selects 3D or Split, or prepare it in
  a low-priority task after the primary results render.
- Lower SceneKit antialiasing or frame rate on thermally constrained devices.
- Avoid rebuilding avatar tracks or overlay meshes when only playback time changes.
- Profile Canvas overlays and marker layout with Instruments.

### Tests and gate

- Video and avatar remain checkpoint-synchronized through play, pause, and scrub.
- Hidden 3D pane does not continuously consume GPU.
- Results screen maintains responsive interaction on the oldest supported beta device.

---

## Phase 7 — Beta UX and product completeness

Implement only after the stability and correctness gates above pass.

### Home and history

- Add generated thumbnails.
- Show processing, failed, interrupted, and completed statuses.
- Add retry, rename, club correction, favorite, and delete actions.
- Add filters for club, angle, and date.
- Add a clear data-management screen for deleting videos and reports.

### Capture

- Add first-run setup onboarding.
- Add tripod height, distance, horizon, lighting, and full-body guidance.
- Use haptic and optional voice cues because the golfer is away from the phone.
- Default to a stable 1080p60 capture profile. Offer 120 fps only when a feature needs it.
- Record actual format metadata; never assume the requested frame rate was achieved.

### Results

- Lead with one primary finding and one next action.
- Put detailed metrics behind progressive disclosure.
- Show confidence and missing-data explanations.
- Add current-vs-previous comparison.
- Add goal progress across several swings.
- Add a shareable summary card only after privacy review.

### Drills and coaching

- Add short drill demonstrations and common mistakes.
- Let users mark a drill as practiced.
- Tie follow-up swings to active goals.
- Personalize narrative using prior measured trends, not invented continuity.

### Accessibility

- Audit VoiceOver order and labels for every custom glyph and control.
- Test Dynamic Type, Reduce Motion, Increase Contrast, and screen zoom.
- Do not communicate faults by color alone.

---

## Phase 8 — Optional new measurement models

Do not begin this phase until the bounded Vision pipeline is stable and measured.

Candidates, in priority order:

1. A small temporal swing-phase classifier operating on pose sequences to improve
   checkpoint detection around waggles, pauses, and unusual tempos.
2. A confidence model that predicts when body orientation, checkpoints, or plane values
   are trustworthy.
3. An on-device club/ball detector combined with optical flow for shaft and clubhead
   tracking.
4. Two-angle DTL/face-on fusion UI using the existing fusion model.

Requirements:

- Keep deterministic geometry as the source of reported biomechanics.
- Version every model and record the version in diagnostics/report metadata.
- Maintain held-out validation footage and per-metric error tolerances.
- Provide an honest fallback when a model cannot produce a trustworthy result.

---

## Phase 9 — Test matrix and beta release gate

### Add an app unit-test target

Cover:

- Video preflight.
- Analysis job transitions.
- Cancellation and retry.
- Store migrations and orphan cleanup.
- Progress throttling.
- Setup metadata propagation.
- Confidence-aware score availability.
- Remote coaching update isolation.

### Integration matrix

Include:

- H.264 and HEVC.
- SDR and HDR.
- 720p, 1080p, and 4K sources.
- 24/25/30/60/120/240 fps sources.
- Portrait and landscape transforms.
- DTL and face-on views.
- Right- and left-handed golfers.
- Short, long, damaged, no-person, partial-body, low-light, and multiple-person clips.
- Backgrounding, low storage, thermal pressure, and interrupted persistence.

### Performance tests

- Record request counts, total time, stage time, and peak memory.
- Fail CI/device benchmark jobs when budgets regress beyond an agreed tolerance.
- Keep performance fixtures separate from UI demo fixtures.

### Documentation

- Create `docs/VALIDATION.md` with fixture provenance, expected checkpoints, measured
  tolerances, known biases, and device benchmark results.
- Keep README claims aligned with verified functionality.
- Document grip proxies and unsupported club metrics clearly.

### Release gate

Do not call the app beta-ready until:

- The service-level objectives at the top of this document have device evidence.
- No known crash or jetsam path is reproducible on supported devices.
- Interrupted jobs recover.
- Results do not wait for the network.
- Scores are confidence-gated.
- Users can correct angle, club, and handedness.
- Delete/export/privacy behavior is documented and tested.
- TestFlight telemetry is reviewed without collecting raw video or pose coordinates.

---

## Recommended commit/PR sequence

Keep these separate:

1. `Add analysis diagnostics and device telemetry`
2. `Introduce cancellable persistent analysis jobs`
3. `Add video preflight and swing setup flow`
4. `Bound Vision sampling and memory usage`
5. `Add confidence-aware reports and scoring`
6. `Decouple enhanced coaching from results`
7. `Optimize results playback and avatar rendering`
8. `Expand beta history, drills, and accessibility`
9. `Add device performance and validation suite`

Each PR must include before/after measurements relevant to its scope.

## First execution task

Begin only with Phase 0. Produce:

- A baseline diagnostics model.
- Stage signposts.
- Throttled progress.
- One device-run reporting format.
- Tests for timing aggregation and redaction.

At the end of Phase 0, stop and report the measured bottlenecks before implementing
Phase 1. The code review predicts the dominant costs, but beta engineering decisions must
be based on real-device evidence.
