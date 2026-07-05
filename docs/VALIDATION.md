# SwingThrough Validation and Device Benchmarks

This document records evidence for measurement accuracy, performance, and beta release
gates. Simulator results prove compilation and UI behavior only; Vision performance,
memory pressure, camera formats, and thermal behavior require a real iPhone.

## Current verification status

- 2026-07-05 — SwingKit debug suite under Xcode 26.6: 57 tests passed, 0 failed,
  1 skipped because the host AVFoundation decoder was unavailable.
- 2026-07-05 — XcodeGen 2.45.4 generated `SwingThrough.xcodeproj` successfully.
- 2026-07-05 — required iPhone 17 Pro Simulator build succeeded under Xcode 26.6.
  The complete Xcode test scheme also passed: 11 app unit tests and 3 UI tests,
  including cold launch, results navigation/playback panes, and cancel-action smoke.
- 2026-07-05 — direct arm64 iOS type-check passed for SwingKit, the complete app,
  `SwingThroughTests`, and `SwingThroughUITests`, including SwiftData/Observation macro
  expansion with compiler subprocess sandboxing disabled.
- 2026-07-05 — `swingctl analyze` exercised failure diagnostics against the bundled
  sample. The host decoder rejected the input with AVFoundation `-11821`; diagnostics
  safely recorded metadata, preflight/coarse timings, memory, thermal state, and the
  stable failure category without recording its path or media content.
- Real-device baseline runs: not yet recorded.

Phase 1 runtime validation additionally covers cancellation identity, one-active-job
coordination, V1→V2 migration, interrupted-job reconciliation, retained-input behavior,
and path containment in the iPhone 17 Pro Simulator.

Phases 2–7 source validation additionally covers typed preflight rejection, trim-window
clamping, setup metadata persistence, FPS-independent Vision request budgets, frame-error
tolerance, confidence-gated/contextual scoring, binary frame lookup, local-first coaching,
single-clock 3D playback, and explicit local-data deletion. Real-device performance,
camera, thermal, and accuracy gates remain open.

## Device-run reporting format

Record one row per run and attach the debug diagnostics JSON exported from Settings.
Never attach the source video, joint coordinates, API key, or coaching text.

| Field | Value |
|---|---|
| Date/time | |
| Diagnostics job ID | |
| App commit | |
| Build configuration | Debug / TestFlight |
| Device model | |
| iOS version | |
| Battery / Low Power Mode | |
| Initial thermal state | nominal / fair / serious / critical |
| Input fixture ID | |
| Source duration | |
| Source dimensions | |
| Source nominal FPS | |
| Codec / SDR-HDR | |
| Capture view | DTL / face-on |
| Coarse sampled frames | |
| Detailed 2D sampled frames | |
| Detailed 3D sampled frames | |
| Recoverable / dropped frames | |
| Stage durations | preflight; coarse; detect; detailed; smoothing; checkpoints; plane; measurements; metrics; persistence; coaching |
| Time to deterministic result | |
| Peak memory | |
| Thermal-state changes | |
| Final result | completed / failed / cancelled / jetsam |
| Stable failure category | |
| Notes | |

## Required Phase 0 baseline

Before changing Vision sampling or memory behavior, collect at least three runs on a real
iPhone using the same five-second 1080p60 input where possible. Use Instruments or the
Xcode memory gauge alongside exported diagnostics to identify the dominant stage and
peak resident memory. If the process is jetsammed, capture the MetricKit diagnostic on a
subsequent launch.

## Beta performance targets

- Five-second 1080p60 video: deterministic results below 15 seconds median and 25 seconds p95.
- Crash-free analysis sessions above 99.5%.
- Valid, properly framed analysis success above 90%.
- Cancellation acknowledgement below one second.
- UI progress updates at no more than 10 Hz.
- Unsupported inputs rejected before detailed 3D analysis.

## Accuracy fixture registry

Populate this section when validation footage is available. Each fixture entry must
record provenance/consent, view, handedness, club, source format, expected checkpoint
times, per-metric tolerances, and known visibility limitations. Do not commit private
user footage to the repository.

| Fixture ID | Provenance | View | Club | FPS | Expected checkpoints | Metric tolerances | Known limitations |
|---|---|---|---|---:|---|---|---|
| bundled-sample | Illustrative fixture; production-report provenance pending | DTL | 7 Iron | 25 | Pending | Pending | Current report must not be treated as validation truth. |
