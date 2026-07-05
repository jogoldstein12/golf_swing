# SwingThrough Beta Features — Specification

This is an execution spec for the next build phase of SwingThrough, following the same
discipline as `BETA_IMPLEMENTATION_SCRIPT.md`: one coherent, reviewable change per item;
tests before moving on; never weaken a gate to pass it. It covers three tracks selected
on 2026-07-05:

1. **Accuracy & Confidence** — make the numbers trustworthy, and honest when they aren't.
2. **Results Experience** — turn measurements into coaching people act on.
3. **Real-World Capture** — make solo, tripod-distance capture actually work.

Explicitly **out of scope for this phase** (deferred, not cancelled): server-mediated
coaching, history/library management UI, and the accessibility audit. Revisit after these
three land.

## Relationship to prior work

- `BETA_IMPLEMENTATION_SCRIPT.md` phases 0–6 are **done** (commit `78e6914`): bounded
  Vision sampling, cancellable persistent jobs, preflight, local-first coaching,
  confidence-aware report scaffolding, diagnostics, data management.
- This spec is the "phase 7+ / accuracy hardening" layer. It assumes that foundation.
- It builds on infrastructure that **already exists** — do not re-invent it (see below).

## Non-negotiable constraints (inherited)

- Deterministic geometry stays the single source of reported biomechanics. **Never** place
  an AI-generated or interpolated value into the measurement layer.
- A number that cannot be trusted must be marked, degraded, or withheld — never shown as
  authoritative. This spec extends that rule, it does not relax it.
- Raw video stays on-device.
- Each item is independently buildable, testable, and revertible. Regenerate the project
  with `tools/bin/xcodegen/bin/xcodegen generate` when files/targets change.
- Gate every item on `SwingKit` tests + the iPhone 17 Pro Simulator build; add focused
  tests with each item.

## Grounding: confidence infrastructure that already exists

Track A extends these — reference them, don't duplicate them (`SwingKit/Sources/SwingKit/Report.swift`):

- `enum MeasurementProvenance { measured, interpolated, inferred, unavailable }`
- `struct MeasurementQuality { confidence, coverage, provenance, warnings }`
- `struct MetricValue { …, quality: MeasurementQuality? }`
- `struct ReportQuality { twoDCoverage, threeDCoverage, checkpointConfidence, orientationConfidence, planeBasis, warnings }`
- `SwingScore.Availability` with `isAvailable` (already gates the score to `.insufficientData`).
- `MetricsBuilder.reportQuality(_:)` and `MetricsBuilder.score(_:metrics:quality:)`.

The gap this spec closes: coverage/orientation confidence is computed, but a report can
still contain **physically impossible values that pass the gate** (see A0).

---

## Track A — Accuracy & Confidence

### A0 — The evidence this track exists to fix

Running the production pipeline (`swingctl analyze`) on the bundled `sample_dtl.mp4`
produced a report with a **4.2° shoulder turn**, **2.6° X-factor at transition**, and a
**19.9° plane deviation** — anatomically impossible for a full swing — yet
`ReportQuality` reported `orientationConfidence ≈ 0.84` and the score returned
`availability: .available`. Coverage was high; the *values* were wrong (degenerate 3D yaw).
Conclusion: coverage is necessary but not sufficient. We must also validate that measured
values are physically plausible before trusting them.

### A1 — Plausibility gating (deterministic)

**Goal.** Catch physically impossible measurements and degrade their provenance/confidence
instead of reporting them as measured.

**Implementation.**
- Add `PlausibilityGate` in `SwingKit/Sources/SwingKit/Pipeline/`. Pure function over a
  built `MetricValue` set + `ReportQuality`. No ML, no thresholds hidden in the UI.
- Define anatomical validity envelopes per metric (wider than the *ideal* band — these are
  "possible for a human," not "good"). Initial envelopes, to be refined against fixtures:
  - Shoulder turn 20–150°, hip turn 5–90°, X-factor 5–80°, spine angle 15–55°,
    plane deviation |Δ| ≤ 25°, tempo 1.0–6.0.
- For any metric outside its envelope: set `MeasurementQuality.provenance = .unavailable`,
  lower `confidence`, and append a specific `warning`. Do **not** silently clamp the value.
- Feed a plausibility signal back into `ReportQuality`: if the 3D-derived rotation family
  (turn/X-factor) is implausible, lower `orientationConfidence` so the existing score gate
  responds. This is the missing link that would have caught A0.

**Tests and gate.**
- Unit-test each envelope boundary (inside → measured; outside → unavailable + warning).
- Regression fixture: the A0 `sample_dtl.mp4` report must resolve to
  `score.availability == .insufficientData` (or the turn metrics marked `.unavailable`),
  not a confident 10/100.
- No previously-valid fixture regresses to `unavailable`.

### A2 — Orientation-aware per-metric provenance

**Goal.** When body-orientation (yaw) confidence is low through the downswing, the metrics
that depend on it degrade individually — not the whole report, and not nothing.

**Implementation.**
- Map each metric to its dependency: turn / X-factor / plane depend on 3D orientation;
  tempo / checkpoint timing do not.
- In `MetricsBuilder`, when `orientationConfidence` is below a documented threshold, set the
  dependent metrics' `provenance = .inferred` (shown with a caveat) or `.unavailable`
  (withheld), never `.measured`.
- Surface `warnings` the UI can render verbatim (feeds B6).

**Tests and gate.**
- Synthetic low-orientation report: dependent metrics degrade, independent ones stay
  `.measured`.
- `ReportQuality.warnings` is non-empty and specific.

### A3 — Accuracy validation harness

**Goal.** Make accuracy regressions detectable in CI, so bounded sampling and gating
changes are provably safe.

**Implementation.**
- Add `docs/VALIDATION.md` fixture rows (extend the existing file): per sample clip, record
  expected checkpoint times (± tolerance) and per-metric expected ranges, sourced from the
  annotated extraction frames.
- Add `AccuracyRegressionTests` in `SwingKitTests` asserting the pipeline stays within those
  tolerances per fixture. Tolerances are per-metric, not byte-identical reports.
- Keep a debug flag to run the pre-bounding (full-FPS) pipeline for A/B comparison until the
  bounded rates are validated.

**Tests and gate.**
- Harness runs in `swift test`; a fixture drifting out of tolerance fails CI.
- Document the tolerance rationale per metric.

### A4 — Real demo sample

**Goal.** Replace the provisional (prototype-number) demo swing with genuine measured data.

**Implementation.**
- **Blocked on A1–A3 or a device capture.** macOS `swingctl` on the current clip yields
  implausible values (A0); do not bundle that. Options, in order of preference:
  1. Capture a clean clip **on-device** (where Vision 3D is materially better), run it
     through the real pipeline, and bundle the resulting `sample_report.json` +
     matching `sample_dtl.mp4`.
  2. If a macOS-analyzable clip clears the A1 plausibility gate with real values, bundle
     that.
- `DemoData` already prefers a bundled `sample_report.json`; once one exists that passes the
  gate, drop it into `SwingThrough/Fixtures/` and delete the provisional path.
- Until then, keep the provisional report **clearly labeled** (the "SAMPLE" pill already
  does this) — do not ship measured-looking numbers that aren't measured.

**Tests and gate.**
- The bundled sample decodes, passes the A1 plausibility gate, and its overlays align with
  the video.

### A5 — Learned confidence model (later)

**Goal.** A model that predicts when orientation / checkpoints / plane are trustworthy,
beyond deterministic envelopes.

**Implementation.** Deferred until A1–A3 are in and we have labeled trust data from
diagnostics. Version the model; record its version in report/diagnostics metadata; keep the
deterministic gate as the floor. This is `BETA_IMPLEMENTATION_SCRIPT.md` Phase 8 territory.

---

## Track B — Results Experience

### B1 — Lead with one finding and one action

**Goal.** The results screen opens on the story, not the data.

**Implementation.**
- A `LeadCard` above the panes: the #1 coaching goal (`report.coaching.goals` is already
  priority-ordered) as the headline, its `current → target`, and its drill as the single
  next action.
- Reuse existing type/`FloatCard` styling; no new visual language.
- If `score.availability == .insufficientData`, the lead card leads with the confidence
  explanation (B6) instead of a headline fault.

**Tests and gate.** Lead card renders the top-priority goal; low-confidence report shows the
confidence state first. UI smoke test in `SwingThroughUITests`.

### B2 — Progressive disclosure of metrics

**Goal.** Detail on demand, not a wall of numbers up front.

**Implementation.**
- Collapse the full metric grid behind a "See all measurements" disclosure; keep the 2–4
  headline metrics visible.
- Each disclosed metric shows its `provenance`/quality (A2) — measured vs inferred vs
  withheld.

**Tests and gate.** Collapsed by default; expands; withheld metrics render as "not measured"
with the reason, never as a value.

### B3 — Current-vs-previous comparison

**Goal.** "Plane 2° better than your last 7-iron."

**Implementation.**
- Query history for the most recent prior swing of the same `club` (+ same `view`); the data
  exists in `SwingRecord`/stored reports.
- Show signed deltas on the headline metrics and score, respecting provenance (don't compare
  against a withheld metric).

**Tests and gate.** Delta logic unit-tested (including "no prior swing" and "prior swing had
withheld metric").

### B4 — Goal progress and "fixed" detection

**Goal.** Show whether a prescribed fault is improving across swings.

**Implementation.**
- Correlate a goal's `metricLabel` across the last N same-club swings; mark a fault "fixed"
  when it holds inside its ideal band for M consecutive swings.
- Coaching continuity uses **measured trends only** — never invented narrative.

**Tests and gate.** Fixed-detection unit-tested against synthetic swing histories.

### B5 — Share card (decision-gated)

**Goal.** A designed, shareable summary image (score + one plane callout + one goal).

**Implementation.** Render off the design system to an image. **Open decision (see below):**
whether this is in scope now. If yes, gate on a privacy check — image only, no video, no
coordinates.

**Tests and gate.** Card renders deterministically; contains no raw frames or coordinates.

### B6 — Low-confidence presentation

**Goal.** When measurement is thin, say so — plainly and usefully.

**Implementation.**
- When `score.isAvailable == false` or metrics are withheld, show the `ReportQuality.warnings`
  and a "how to get a cleaner read" hint (framing/lighting/full-body), reusing the existing
  capture-failure copy voice.
- Never render a precise 0–100 score under the insufficiency state.

**Tests and gate.** Insufficient report never shows a numeric score; warnings render verbatim.

---

## Track C — Real-World Capture

The golfer is 6–10 ft from a tripod and cannot read the screen or hear a quiet tone. Capture
must communicate by sound and feel.

### C1 — Audio + haptic cues and a spoken countdown

**Goal.** Know the capture state without looking at the phone.

**Implementation.**
- Distinct audio cues on state transitions in `CaptureController`: armed, recording started,
  swing captured, and a **spoken 3-2-1 countdown** for the manual path.
- Haptics (`UIImpactFeedbackGenerator` / `UINotificationFeedbackGenerator`) mirroring each
  transition, felt when the golfer walks back to the phone.
- Respect the silent switch / accessibility settings; provide a toggle. Cues are additive —
  they must not alter capture timing or the detector state machine.

**Tests and gate.** Cue fires exactly once per transition (unit-test the state→cue mapping);
no cue path mutates `SwingDetector` timing. Verify on device that armed/recording/captured
are distinguishable by ear at tripod distance.

### C2 — First-run capture onboarding

**Goal.** Teach a good setup before the first swing.

**Implementation.**
- A short first-run walkthrough: tripod height, distance (full body in frame), DTL vs
  face-on, lighting — driven by the **live checklist that already exists**
  (`SetupChecklist`), so the walkthrough is interactive, not static slides.
- Show once; re-openable from Settings.

**Tests and gate.** Shows on first launch only (persisted flag); the live checklist drives
its "you're set" state.

### C3 — Stable capture profile + honest format metadata

**Goal.** A predictable capture format, and truth about what was actually recorded.

**Implementation.**
- Default to a stable 1080p60 profile; offer 120 fps only where a feature needs it.
- Record the **achieved** format (dimensions, actual frame rate) into the report/diagnostics
  — never assume the requested rate was honored.
- Analysis reads the achieved rate, not a nominal constant.

**Tests and gate.** Achieved-format metadata is populated and flows into diagnostics; analysis
uses it.

---

## Sequencing

**Opening sprint** — three independent, low-risk, high-leverage first moves, one per track:

- **A1** Plausibility gating (fixes the A0 bug; unblocks a real demo sample).
- **B1 + B2** Lead card + progressive disclosure (biggest perceived-quality jump; no new data).
- **C1** Audio + haptic cues + spoken countdown (makes solo capture usable).

**After the sprint:** A2 → A3 (accuracy harness) → A4 (demo sample); B3 → B4 (comparison /
progress); C2 → C3 (onboarding / format). A5 and B5 are decision-/data-gated.

## Open decisions (need product sign-off)

1. **Share card (B5)** — in scope this phase, or defer with the rest of the sharing/privacy
   work? *Recommendation: defer; design it, ship it after a privacy pass.*
2. **Capture cues (C1)** — voice, haptics, or both? *Recommendation: both, with a toggle;
   voice is the primary signal at tripod distance, haptics confirm on approach.*
3. **Confidence approach (A5)** — confirm we do deterministic gating (A1/A2) now and treat the
   learned model as a later, separate effort. *Recommendation: yes.*

## Acceptance gate for this phase

- The A0 sample no longer yields a confident score; implausible metrics are withheld.
- The accuracy harness (A3) runs in CI and guards the bounded-sampling rates.
- Results lead with a finding + action and disclose the rest, with confidence shown.
- Capture state is perceivable without looking at the screen.
- `SwingKit` tests + iPhone 17 Pro Simulator build stay green; each item ships with tests.
- Device evidence recorded in `docs/VALIDATION.md` for anything with runtime performance.

## Recommended commit sequence

1. `Add plausibility gating for implausible measurements` (A1)
2. `Degrade orientation-dependent metric provenance` (A2)
3. `Add accuracy regression harness and fixtures` (A3)
4. `Results: lead card + progressive metric disclosure` (B1/B2)
5. `Results: current-vs-previous and confidence presentation` (B3/B6)
6. `Capture: audio + haptic cues and spoken countdown` (C1)
7. `Capture: first-run onboarding` (C2)
8. `Capture: stable 1080p60 profile + achieved-format metadata` (C3)

Each commit includes its tests and, where it touches runtime performance or accuracy,
before/after evidence.
