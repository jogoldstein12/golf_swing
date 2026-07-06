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

The registry is enforced in CI by `AccuracyRegressionTests` (SwingKitTests). Each row is
a fixture the harness runs through the real pipeline, asserting checkpoint times and
per-metric measured values stay inside their tolerance windows (not byte-identical
reports). A fixture that drifts out of tolerance fails CI. Add a fixture by extending
`AccuracyRegressionTests.fixtures` with the row's expected windows and adding the row
below. On a host without an AVFoundation decoder for the clip (the CLI/`swift test` host —
see the `-11821` note above) each fixture skips cleanly; the iPhone Simulator scheme runs
them fully.

| Fixture ID | Provenance | View | Club | FPS | Expected checkpoints | Metric tolerances | Known limitations |
|---|---|---|---|---:|---|---|---|
| bundled-sample | Illustrative fixture; production-report provenance pending | DTL | 7 Iron | 25 | P1 1.0–2.0s · P4 2.5–3.4s · P7 3.2–4.0s · P10 4.5–5.8s | Tempo 1.7–3.0 · Spine Angle 33–48° · Spine Angle Change 18–34° · Pelvis Thrust 0.8–2.8in | Degenerate 3D yaw; turn family withheld and score `insufficientData` (A0 gate). Only orientation-INDEPENDENT metrics are pinned — the withheld turn family is not. |

**WS-D annotation note (2026-07-05):** this fixture was annotated by running the current
pipeline (`swingctl analyze`) on the committed clip and hand-setting windows around the
measured output, with margin for macOS-CLI-vs-iOS-Simulator Vision variance. It gives
positive validation of the trustworthy (tempo/posture) metrics *and* confirms the
withholding of the untrustworthy turn family in a single fixture. A clean swing that
scores `.available` end-to-end remains desirable future footage (private/consented), but
is intentionally not committed here (16 MB, externally sourced).

### A0 gate (bundled-sample)

The bundled clip is the A0 evidence fixture (docs/BETA_FEATURES_SPEC.md): the production
pipeline produced a 4.2° shoulder turn / 2.6° X-factor / 19.9° plane report while
reporting `orientationConfidence ≈ 0.84` and `availability: .available`. With A1
plausibility gating in place, the harness asserts this fixture resolves to
`score.availability == .insufficientData` (or its turn metrics marked `.unavailable`).
This is asserted deterministically — independent of any decoder — by
`PlausibilityGateTests.testA0DegenerateReportNoLongerScoresConfident`, which reproduces
the exact metric/quality inputs and checks the gate flips the score.

### Per-metric tolerance rationale

When real annotated footage lands, populate `metricTolerances` per fixture. Rationale for
the intended windows (wider than ideal bands — these test that the *measurement* is
stable, not that the swing is good):

- **Checkpoint times** — ±1 frame at the achieved capture rate (≈ ±0.033 s at 30 fps),
  since checkpoint detection resolves to a sampled frame.
- **Tempo** — ±0.3 (:1); ratio of two checkpoint intervals, so it inherits ~2× the
  single-checkpoint timing error.
- **Spine angle at address** — ±3°; single-frame tilt, no cross-frame stabilization.
- **Shoulder / hip turn, X-factor** — ±8°; these ride the 3D-orientation stream and its
  documented yaw-rigidity compression. Only asserted when provenance is `.measured` (a
  gate-withheld value is allowed to drift).
- **Swing plane deviation** — ±2.5°; image-space grip-path geometry, the most trusted 3D
  number.

### Plausibility envelopes (A1)

Anatomical validity envelopes gating implausible measurements (`PlausibilityGate`), wider
than the ideal bands in SWING_MODEL.md — "possible for a human," not "good":

| Metric | Envelope | Withheld when outside |
|---|---|---|
| Shoulder turn | 20–150° | provenance → `.unavailable`, orientation confidence collapsed |
| Hip turn | 5–90° | provenance → `.unavailable`, orientation confidence collapsed |
| X-factor at transition | 5–80° | provenance → `.unavailable`, orientation confidence collapsed |
| Spine angle | 15–55° | provenance → `.unavailable` |
| Swing plane deviation | |Δ| ≤ 25° | provenance → `.unavailable` |
| Tempo | 1.0–6.0 (:1) | provenance → `.unavailable` |

### Orientation-provenance thresholds (A2)

Fraction of trusted-orientation frames through the swing, from
`BodyOrientation.orientationTrustMask`:

- ≥ 0.60 — orientation-dependent metrics (turn / X-factor / plane) reported `.measured`.
- 0.35–0.60 — those metrics degrade to `.inferred` (shown as an estimate with a caveat).
- < 0.35 — those metrics are withheld (`.unavailable`); the score's orientation gate also
  trips, so the whole total resolves to `insufficientData`.
- Orientation-independent metrics (tempo, posture, translational DOF) are never degraded
  by this rule.

### Full-FPS A/B (bounded-sampling validation)

Until the bounded Vision sample rates (coarse 12 fps / detailed 30 fps) are validated
against footage, compare against a full-FPS run for the same clip: run `swingctl analyze`
on the fixture and diff the report against a full-rate pass. Keep the bounded rates only
where the A/B metric deltas stay inside the tolerance windows above. Record the A/B deltas
in a device-run row when footage is available.
