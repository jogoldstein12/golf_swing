# Coaching Integrity & Scoring Accuracy — Spec

> **For agentic workers:** This is a self-contained spec, not a step-by-step plan. Each workstream (WS-*) is independently shippable and carries its own acceptance criteria + representative tests. Implement via `superpowers:subagent-driven-development` under the multi-agent orchestration in §7. Steps use TDD: failing test first, minimal fix, green, commit. Checkbox (`- [ ]`) items are ship-gates, not micro-steps.

**Goal:** Stop the coaching layer from giving confident advice on measurements the pipeline itself distrusts, make the score reflect measurement reliability rather than only importance, and close the results UX from *diagnosis* to *practice* — implemented with a cost-efficient multi-agent workflow.

**Architecture:** Five independent workstreams. WS-A/B/C/D are pure `SwingKit` (Swift package, unit-testable headless via `swift test`). WS-E is the SwiftUI app (`SwingThrough/`, verified in the iPhone 17 Pro simulator). The gate's existing `MeasurementProvenance` signal becomes the single source of truth that propagates all the way to coaching and display; nothing new is invented where a signal already exists.

**Tech Stack:** Swift 6 / SwiftUI, `SwingKit` SPM package, XCTest, xcodegen + Xcode 26.6, Anthropic Messages API (`claude-opus-4-8`, forced tool use) for the Claude coach.

## Global Constraints

- **Toolchain:** build/test with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. `swift test --package-path SwingKit` for SwingKit; `xcodegen generate` then `xcodebuild test -scheme SwingThrough -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` for the app. Fonts must be staged first: `zsh assets/fetch_fonts.sh`.
- **No fabricated measurements.** A distrusted value is never clamped, defaulted, or shown as if real (existing `PlausibilityGate` doctrine, `PlausibilityGate.swift:10-11`). Withholding is always preferred over guessing.
- **Determinism preserved.** `CoachingPayloadEncoder` output stays `Equatable` and golden-file testable; no `Date.now()`/random in pipeline code.
- **Provenance vocabulary (verbatim):** `MeasurementProvenance` = `.measured | .interpolated | .inferred | .unavailable` (`Report.swift:39-43`). `.unavailable` = withheld, must never drive advice. `.interpolated`/`.inferred` = usable but flagged.
- **Score availability (verbatim):** `SwingScore.availability: Availability?`, `.insufficientData` sentinel, `isAvailable == (availability != .insufficientData)` (`Report.swift:230,250`).
- **Backward compatible JSON:** bump `SwingReport.schemaVersion` only if a field is removed; additive fields need no bump.
- **TDD + frequent commits**, one workstream deliverable per commit, conventional-commit messages, `Co-Authored-By: Claude Opus 4.8 (1M context)` trailer.

---

## Problem (evidence from the 2026-07-05 audit)

1. **The gate's caution dies at the coaching boundary.** `PlausibilityGate.apply` flips a distrusted metric's `provenance` to `.unavailable` but keeps its garbage `value` verbatim (`PlausibilityGate.swift:59-72`). Neither coach reads provenance: `RuleBasedCoach` selects on value-only `inBand` (`RuleBasedCoach.swift:16-17` → `checkTempo`/`checkTurn`), and `CoachingPayloadEncoder` encodes every metric with **no provenance field** (`CoachingPayloadEncoder.swift:45-52, 116-119`). **Demonstrated live:** on `faceon_driver_b`, a withheld 7.2° shoulder turn / 0.8° X-Factor still produced a confident Claude goal *"Widen and complete the backswing turn"* — while the results screen simultaneously showed "Not measured / Not scored." The score's `insufficientData` only demoted that goal #1→#4; it never suppressed or caveated it.
2. **`ClaudeCoach` timeout is 8s** (`ClaudeCoach.swift:21`) — too short for an Opus structured-output call; it fails as an opaque `network("request failed")` (`ClaudeCoach.swift:71`), swallowing the real error. Reproduced live.
3. **Score weights importance, not measurability.** On face-on clips ~67% of the total rides the two least-reliable measurements — Kinematic Sequence (highest weight; pelvis/torso series share the same yaw signal so their peak-*order* is largely noise, `SegmentSeries.swift:19-27`) and turn-at-top (interpolated across the frames `BodyOrientation.swift:88-95` documents as unreliable) — while the most trustworthy number (Swing Plane, DTL) contributes 0. `orientationConfidence` is averaged over the whole clip (`MetricsBuilder.swift:247-249`), so a clean address/impact can mask a corrupt top.
4. **No positive accuracy validation exists.** `VALIDATION.md` fixtures are "pending annotation"; the only enforced accuracy assertion is the negative A0 garbage-rejection gate.
5. **UX is a diagnostic, not a practice loop.** Honest about uncertainty (a real strength) but the takeaway renders below a 400pt video, goal #1 is duplicated, provenance tags leak jargon, there's no insight→drill→practice path, and no longitudinal trend.

## Scope

**In:** WS-A coaching integrity (provenance propagation + availability reconciliation + `CoachGoal.cue`), WS-B coach reliability (timeout + error surfacing), WS-C scoring recalibration (sequence/turn confidence + orientation windowing), WS-D one annotated validation fixture, WS-E the coaching canvas + practice loop (on-frame overlays, glance strip, drill/`FocusRecord` loop; fully designed in the visual-coaching-canvas spec).

**Out (this cycle):** new metrics, ML pose models, multi-camera fusion, a full longitudinal analytics backend, drill-video content. A longitudinal *sparkline* (WS-E) is in; a full trends dashboard is out.

---

## WS-A — Coaching integrity: provenance in, no advice on garbage

**Problem:** withheld/`.unavailable` metrics drive confident advice in both coaches; `insufficientData` is ignored by both.

**Files:**
- Modify: `SwingKit/Sources/SwingKit/Coaching/RuleBasedCoach.swift` (metric tiers `checkTempo`, `checkTurn`, `refinementGoals`)
- Modify: `SwingKit/Sources/SwingKit/Coaching/CoachingPayloadEncoder.swift` (`MetricPayload` struct `:45-52`, `encode` `:116-119`, `ScorePayload`)
- Modify: `SwingKit/Sources/SwingKit/Coaching/ClaudeCoach.swift` (system prompt `:187+`)
- Modify: `SwingKit/Sources/SwingKit/Coaching/RuleBasedCoach.swift` + `ClaudeCoach.swift` (availability reconciliation)
- Test: `SwingKit/Tests/SwingKitTests/CoachingRuleBasedTests.swift`, `CoachingPayloadEncoderTests.swift`, `CoachingClaudeTests.swift`

**Decisions (filled blanks):**
- Single shared helper on the report: `report.coachableMetrics` = `metrics.filter { $0.quality?.provenance != .unavailable }`. Both coaches consume this, never raw `report.metrics`, for fault selection. (Mirror of the existing correct pattern at `MetricsBuilder.swift:174`.)
- `MetricPayload` gains `provenance: String` (from `quality?.provenance.rawValue ?? "measured"`). `.unavailable` metrics are **excluded entirely** from the payload; `.interpolated`/`.inferred` are included but flagged so the model can hedge.
- `ScorePayload.availability` already exists; add a top-level `Payload.reliability: String` = `"reliable"` when `score.isAvailable` else `"low_confidence"` for prompt prominence (don't rely on the model spelunking the score object).
- Availability reconciliation: when `!report.score.isAvailable`, the **lead** goal must be a capture-quality message, and confident metric goals are capped (rule coach: return at most 1 measured-fault goal + the capture message; Claude prompt: instructed to lead with capture guidance and mark remaining goals as tentative). Neither coach fabricates faults to hit a goal count — the existing "≥2 goals" floor (`RuleBasedCoach.swift:24`) is relaxed to allow a single capture-quality goal.
- Claude system prompt additions: (a) "Metrics with provenance `interpolated`/`inferred` are estimates — hedge, don't prescribe hard targets from them." (b) "If reliability is `low_confidence`, your first goal MUST address capture quality, and you may return as few as ONE additional goal." Update the "never return zero goals / 2-4 goals" instruction accordingly.
- **`CoachGoal.cue: String?`** (external-focus caption, feeds WS-E's canvas). A short (≤ ~8-word) effect-focused imperative — name the club/target/effect, never a body part ("Drop the club into the corridor", not "Shallow your shaft"). `RuleBasedCoach` maps each fault tier to a fixed cue (deterministic, golden-testable); `ClaudeCoach` prompt + tool schema require a `cue` per goal under the same external-focus rule. Additive Codable field — no schema bump; only ever attached to a `coachableMetrics` goal, so withheld faults get no cue.

**Acceptance criteria:**
- [ ] A `.unavailable` metric never appears in `CoachingPayloadEncoder.Payload.metrics`.
- [ ] `RuleBasedCoach` never emits a `CoachGoal` whose `metricLabel` is an `.unavailable` metric.
- [ ] On an `insufficientData` report, both coaches lead with a capture-quality goal and emit no confident hard-target goal derived from a withheld metric.
- [ ] Every emitted `CoachGoal` on a `coachableMetrics` fault carries a non-empty external-focus `cue` (no body-part-only phrasing); `RuleBasedCoach` cues are deterministic/golden-tested.
- [ ] `CoachingPayloadEncoder` stays deterministic/`Equatable`; golden test updated.

**Representative tests (TDD anchors — write these red first):**
```swift
// CoachingPayloadEncoderTests
func testWithheldMetricIsNotSentToModel() {
    let r = reportWithMetric("Shoulder Turn", value: 7.2, provenance: .unavailable)
    let payload = CoachingPayloadEncoder.encode(report: r, context: .empty)
    XCTAssertFalse(payload.metrics.contains { $0.label == "Shoulder Turn" })
}
func testInterpolatedMetricCarriesProvenance() {
    let r = reportWithMetric("Hip Turn", value: 30, provenance: .interpolated)
    let p = CoachingPayloadEncoder.encode(report: r, context: .empty)
    XCTAssertEqual(p.metrics.first { $0.label == "Hip Turn" }?.provenance, "interpolated")
}
// CoachingRuleBasedTests
func testRuleCoachDoesNotCoachOnWithheldMetric() async throws {
    let r = reportWithMetric("X-Factor at Transition", value: 0.8, provenance: .unavailable)
    let plan = try await RuleBasedCoach().coach(r, context: .empty)
    XCTAssertFalse(plan.goals.contains { $0.metricLabel == "X-Factor at Transition" })
}
func testInsufficientDataLeadsWithCaptureQuality() async throws {
    let r = insufficientDataReport()
    let plan = try await RuleBasedCoach().coach(r, context: .empty)
    XCTAssertEqual(plan.goals.first?.metricLabel, "Capture")   // sentinel label for capture-quality goal
}
```

---

## WS-B — Coach reliability: real timeout, real errors

**Problem:** 8s timeout kills legitimate Opus calls; the real error is masked as `network("request failed")`.

**Files:** Modify `SwingKit/Sources/SwingKit/Coaching/ClaudeCoach.swift` (`:21` default timeout, `:69-72` catch); `SwingKit/Sources/swingctl/Coach.swift:43` (pass through). Test: `SwingKit/Tests/SwingKitTests/CancellationTests.swift` (extend) or new `ClaudeCoachErrorTests.swift`.

**Decisions:** default `timeout = 45`. In the catch, wrap the underlying error: `CoachingError.network("request failed: \(error.localizedDescription)")` (still no key leakage — the key lives in a header, not the message). Keep `CancellationError` passthrough.

**Acceptance criteria:**
- [ ] Default `ClaudeCoach().timeout == 45`.
- [ ] A simulated `URLSession` failure surfaces the underlying `localizedDescription` in the thrown `CoachingError`.

```swift
func testNetworkErrorSurfacesUnderlyingCause() async {
    let coach = ClaudeCoach(session: failingSession(NSError(domain: "x", code: -1001, // timedOut
        userInfo: [NSLocalizedDescriptionKey: "The request timed out."])))
    await assertThrows(coach.coach(report, context: .empty)) { err in
        XCTAssertTrue("\(err)".contains("timed out"))
    }
}
```

---

## WS-C — Scoring recalibration: reliability-weighted total

**Problem:** the total leans on the least-reliable measurements; degenerate sequence order and interpolated turn can score confidently.

**Files:** Modify `SwingKit/Sources/SwingKit/Pipeline/MetricsBuilder.swift` (component scoring `:200-231`, orientationConfidence `:247-249`), `SwingKit/Sources/SwingKit/Pipeline/KinematicSequenceAnalyzer.swift` (`:66-71` low-confidence), `SwingKit/Sources/SwingKit/Pipeline/SegmentSeries.swift` (expose a degeneracy signal). Tests: `KinematicSequenceTests.swift`, `AccuracyRegressionTests.swift`, new `ScoreReliabilityTests.swift`.

**Decisions (filled blanks — tune during WS-D once a real fixture lands):**
- **Sequence degeneracy gate:** if pelvis and torso peak times are within `sequenceDegenerateWindow = 0.033s` (≈1 frame @30fps) OR the shared-yaw component dominates local delta (|localDelta| < `SegmentSeries` rigidity floor), mark the Sequence component **low-confidence**: its weight is redistributed to the reliable components (plane, tempo, posture) rather than scored. Emits a `warning` so the UI can explain.
- **orientationConfidence windowing:** compute confidence over the P4/P5 checkpoint neighborhood (±0.15s), not the whole clip. Keep the existing `.insufficientData` gate threshold but feed it the windowed value.
- **X-Factor / turn-at-top honesty:** when derived from interpolated yaw at P4, tag the metric `.inferred` (not `.measured`). Do **not** widen the ideal band (keeps the coaching target correct); instead the `.inferred` tag makes WS-A hedge the advice and WS-E show a caution. (Open decision: band-widening deferred — see §8.)

**Acceptance criteria:**
- [ ] A synthetic report with pelvis/torso peaks 10ms apart scores the Sequence component as low-confidence (weight redistributed), not a confident 0 or 1.
- [ ] `orientationConfidence` is computed from P4/P5-window frames; a clip clean everywhere except the top yields `insufficientData` for turn metrics.
- [ ] Turn/X-Factor derived from interpolated yaw carry `provenance == .inferred`.
- [ ] `AccuracyRegressionTests` still pass (no fixture drifts out of tolerance).

```swift
func testCoincidentPeaksMarkSequenceLowConfidence() {
    let seq = KinematicSequence(peaks: peaksAt(pelvis: 1.000, torso: 1.008, leadArm: 1.10, club: 1.15))
    let comp = MetricsBuilder.scoreComponents(sequence: seq, /* … */)
    XCTAssertTrue(comp.first { $0.label == "Sequence" }!.isLowConfidence)
}
```

---

## WS-D — Land one annotated validation fixture

**Problem:** no positive ground truth; tolerances are placeholders.

**Files:** Add fixture video + annotation to `SwingKit/Tests/SwingKitTests/Fixtures/` (or app bundle path used by `AccuracyRegressionTests.fixtureURL`); modify `AccuracyRegressionTests.swift` fixtures array + `docs/VALIDATION.md` registry.

**Decisions:** pick one clean down-the-line iron swing that the pipeline currently scores `available` (e.g. the `dtl_range_d` sample, scored 71/100). Hand-annotate checkpoint time windows (P1–P10) and per-metric tolerance bands for the trustworthy metrics only (Swing Plane, Tempo, Spine@address); leave turn/sequence tolerances wide/omitted until multi-camera ground truth exists. Record provenance of the annotation in `VALIDATION.md` (who/how/date).

**Acceptance criteria:**
- [ ] `AccuracyRegressionTests` contains ≥1 fixture with real (non-empty) `checkpoints` and `metricTolerances`, passing in the simulator scheme.
- [ ] `VALIDATION.md` registry row updated from "pending" to annotated, with method noted.

---

## WS-E — Results UX: the coaching canvas + practice loop

**Problem:** honest but buried; the video is scrolled past rather than *used* to coach; no practice loop. The design-gated questions are now resolved — full design record (research, decisions, component breakdown, data flow, testing) in **`docs/superpowers/specs/2026-07-05-visual-coaching-canvas-design.md`**. This section is the build contract.

**Locked design decisions (2026-07-05 brainstorm):**
1. Target overlay: **corridor by default; self-ghost** (the user's own prior clean same-club/same-view swing) **once earned**. No fabricated ideal.
2. Screen order: **quiet glance strip → coaching canvas → progressive depth**.
3. Strip: **light/calm, score present but not shouted**.
4. Practice loop: **light — drill page + a pinned carry-forward `FocusRecord`, verified next session**.

**Files:**
- New: `SwingKit/Sources/SwingKit/Coaching/SwingOverlay.swift` (fault→`OverlayPlan` resolver, headless-unit-testable), `SwingThrough/Screens/Analysis/CoachingCanvas.swift`, `SwingThrough/Screens/Analysis/GlanceStrip.swift`, `SwingThrough/Screens/Drills/DrillDetailScreen.swift`.
- Modify: `AnalysisScreen.swift` (re-order; absorb `LeadCard`'s one-thing into strip + caption; keep `LowConfidenceLead`), `AnalysisComponents.swift` (`MeterRow` provenance → plain language, `GoalCard` tappable drill), `HomeScreen.swift` (active-focus card), `SwingThrough/Store/SwingSchema.swift` (+`FocusRecord`, `SwingThroughSchemaV3` lightweight migration), `RootView.swift` (route to `DrillDetailScreen`, focus-prefilled capture), `DrillsScreen.swift` (route to detail).
- Test: `SwingKit/Tests/SwingKitTests/SwingOverlayTests.swift`; `SwingThroughUITests/` (`GlanceStripTests`, `PracticeLinkTests`, no-jargon assertion, insufficient-path assertion).

**Decisions (filled blanks):**
- `SwingOverlay.plan(goal:report:prior:skill:)` gates on `report.coachableMetrics` — a `.unavailable` metric can **never** yield a drawing primitive. Overlay geometry from `PlaneAnalysis.basePlaneAngle` + `deviationByPosition` + `stateByPosition: [SwingPosition: PlaneState]`; corridor band from the metric `ideal` range. Checkpoint resolved by metric family (mirror `Drills.forLabel` + `SwingComparison.metric(for:in:)`).
- Reference selection: emit `.ghostClub` + `.moveArrow` when a clean prior same-club/same-view swing exists whose relevant metric is `.measured`; else `.targetCorridor`. Ghost time-synced **checkpoint-to-checkpoint** (P4→P4), not clock time.
- Face-on (`PlaneAnalysis.Basis == nil`): held reference line + turn cue, **no** plane corridor.
- Progressive disclosure by skill: novice = one line + corridor + caption; advanced adds held reference line, path trace, and the kinematic-sequence panel — which reads WS-C's low-confidence flag and refuses to draw a confident staircase when the sequence is degenerate.
- Caption source is `CoachGoal.cue` (WS-A); when `cue == nil` (old reports) fall back to a neutral cue derived from `goal.title`.
- `FocusRecord` @Model fields: `club`, `viewRaw`, `goalTitle`, `metricLabel`, `cue`, `drillName`, `createdAt`, `resolvedSwingID: UUID?`; ≤1 active per (club, view); resolved by the next same-club swing via `SwingComparison.goalTrend`/`trend`.

**Acceptance criteria:**
- [ ] `SwingOverlay` never emits a drawing primitive for an `.unavailable` metric (headless unit test).
- [ ] A steep-plane report resolves to seek P4/P5 with actual-plane + corridor primitives; with a clean prior swing it swaps to ghost + move-arrow.
- [ ] Goal #1 appears exactly once; every drill is tappable → `DrillDetailScreen`; "Work on this" pins a `FocusRecord` and Home surfaces it.
- [ ] No results view shows the raw words "Inferred"/"Interpolated"; the `insufficientData` path shows the low-confidence lead and **no** fault overlay.
- [ ] `SwingThroughSchemaV3` migrates a V2 store losslessly (lightweight migration).

```swift
// SwingOverlayTests — the honesty gate, headless
func testWithheldMetricYieldsNoOverlayPrimitive() {
    let r = reportWithMetric("Swing Plane", value: 0, provenance: .unavailable)
    let plan = SwingOverlay.plan(goal: goalFor("Swing Plane"), report: r, prior: nil, skill: .beginner)
    XCTAssertFalse(plan.primitives.contains { $0.isPlaneLine })
}
func testCleanPriorSwingSwapsCorridorForGhost() {
    let prior = reportWithMetric("Swing Plane", value: 58, provenance: .measured)
    let curr  = reportWithMetric("Swing Plane", value: 70, provenance: .measured)
    let plan = SwingOverlay.plan(goal: goalFor("Swing Plane"), report: curr, prior: prior, skill: .beginner)
    XCTAssertTrue(plan.primitives.contains { $0.isGhost })
    XCTAssertFalse(plan.primitives.contains { $0.isCorridor })
}
```

---

## §7 — Multi-agent dynamic workflow (speed + cost efficiency)

This is how the spec gets **built**, not just what gets built. WS-A/B/C/D are backend and independently testable; WS-E is app-side. The orchestration exploits that independence, and tiers model/effort by task difficulty so cheap mechanical work never pays for expensive reasoning.

**Shared-hub caveat (learned during design).** True file-level disjointness is imperfect: `Report.swift` (CoachGoal.cue for WS-A, any low-confidence score-component flag for WS-C) and `ClaudeCoach.swift` (WS-A prompt + WS-B timeout) are shared hubs. So the lanes are drawn to **own whole files**, not overlap them: coaching files (WS-A + WS-B + `CoachGoal.cue`) merge as one lane; scoring (WS-C) is a second; WS-E app-side a third; `Report.swift` edits are batched into the first lane and consumed by the others via the typed interface. This keeps worktree isolation conflict-free at the cost of slightly coarser lanes.

**Lane independence & isolation.** After the shared-hub batching above, lanes touch disjoint files → run concurrently in `isolation: 'worktree'` agents. WS-D depends on WS-C's `.inferred` tagging only for its turn tolerances, so it runs after WS-C in the same lane; its plane/tempo annotations are independent and can start immediately. WS-E depends on WS-A's `CoachGoal.cue` + `coachableMetrics`, so its `SwingOverlay` core starts against those typed interfaces and integrates when the coaching lane lands.

**Per-lane pipeline = TDD stages, no barrier between lanes.** Each lane is a `pipeline()` of `write-failing-test → implement → run-tests → adversarial-verify`. Lanes flow independently: WS-B (tiny) finishes and merges while WS-C (largest) is still implementing — wall-clock ≈ the slowest single lane, not the sum.

**Model / effort tiering (the cost lever):**
- Mechanical stages (WS-B timeout, WS-E de-dupe/rename, test scaffolding) → `effort: 'low'`, cheaper tier. These are typo-simple; high reasoning is wasted spend.
- Judgment stages (WS-C reliability math, WS-A prompt + reconciliation design) → default/session model at `effort: 'high'`. Correctness-critical, worth the tokens.
- Verification stages → a *separate, adversarial* agent instructed to **refute** the change (find an input where a withheld metric still reaches advice, or the score still over-confidently ranks a degenerate sequence). Default `refuted=true` unless it can prove safety. This catches the exact class of bug WS-A fixes.

**Dynamic scaling.** If a token budget is set (`+Nk`), scale the verification fan-out: `verifiers = budget.total ? clamp(2, floor(budget.remaining()/80_000), 5) : 2`. With no budget, 2 verifiers per correctness-critical lane (WS-A, WS-C), 1 for mechanical lanes. Loop WS-A verification **until dry** (two consecutive verifier rounds surface no new leak path) rather than a fixed count — the leak surface is unknown-size.

**Sketch (illustrative — the executor fills exact prompts):**
```js
export const meta = {
  name: 'coaching-integrity',
  description: 'Build WS-A..E: provenance-safe coaching, reliable coach, reliability-weighted score, UX',
  phases: [{title:'Implement'},{title:'Verify'},{title:'Integrate'}],
}
const LANES = [
  {id:'WS-B', effort:'low',  worktree:true},
  {id:'WS-E-mech', effort:'low', worktree:true},
  {id:'WS-A', effort:'high', worktree:true, critical:true},
  {id:'WS-C', effort:'high', worktree:true, critical:true},
]
const built = await parallel(LANES.map(L => () =>
  pipeline([L],
    l => agent(`Implement ${l.id} per spec §${l.id}, TDD: failing test first. Return diff summary + test results.`,
               {phase:'Implement', effort:l.effort, isolation:'worktree'}),
    (impl, l) => {                       // adversarial verify, looped-until-dry for critical lanes
      const rounds = l.critical ? 2 : 1
      return parallel(Array.from({length: rounds*(l.critical?2:1)}, (_,i) => () =>
        agent(`Try to REFUTE ${l.id}: find an input where the fix fails (e.g. a withheld metric still reaching advice). Default refuted=true unless proven safe. Impl: ${impl}`,
              {phase:'Verify', effort:'high', schema:VERDICT})))
        .then(vs => ({l, impl, safe: vs.filter(Boolean).every(v=>!v.refuted)}))
    }
  ).then(r => r[0])
))
// WS-D after WS-C in its own short lane; integration + full swift test as a final barrier.
```

**Guardrails:** every worktree lane ends by running `swift test --package-path SwingKit` (or the simulator scheme for WS-E) inside its worktree before reporting safe; the human reviews each lane's diff at the two-stage gate (`subagent-driven-development`) before merge to `Main`. Log any lane that a verifier could not clear — never silently merge an unverified critical lane.

---

## §8 — Sequencing, risks, open decisions

**Sequencing:** WS-A, WS-B, WS-C, WS-E-mech in parallel (day 1). WS-D and WS-E-design after WS-C's `.inferred` tagging exists. Integration barrier: full `swift test` + simulator test action green before merge.

**Risks:**
- WS-C thresholds (`sequenceDegenerateWindow`, orientation window ±0.15s) are best-guess until WS-D ground truth exists → land them behind the fixture and re-tune; keep them named constants, not literals.
- Prompt changes (WS-A) are non-deterministic to validate → rely on the deterministic payload test (withheld metric absent) as the hard gate; treat live-model spot-checks as advisory.

**Open decisions:**
1. X-Factor band-widening vs `.inferred`-tag-only — spec defaults to tag-only; revisit if WS-D shows the sensor's real range is stable.
2. ~~WS-E takeaway-vs-video ordering and the "practice" loop shape~~ — **RESOLVED** by the 2026-07-05 brainstorm; see `docs/superpowers/specs/2026-07-05-visual-coaching-canvas-design.md` and the rewritten WS-E above.
3. Capture-quality goal representation — spec uses a sentinel `metricLabel == "Capture"`; confirm the UI treats it as a non-metric card.
4. WS-E overlay geometry calibration, face-on overlay set, and ghost checkpoint-sync — flagged as build-time calibration items in the design spec; validate against the WS-D fixture.

## §9 — Self-review coverage

| Audit finding | Workstream |
|---|---|
| Withheld metrics reach both coaches | WS-A |
| `insufficientData` ignored by coaches | WS-A |
| Verbal body-cues instead of external-focus visual targets | WS-A (`CoachGoal.cue`) + WS-E |
| 8s timeout / masked errors | WS-B |
| Score weights unreliable metrics; sequence degeneracy; whole-clip orientation confidence | WS-C |
| No positive validation | WS-D |
| Video scrolled past, not used to coach; no on-frame fault→fix | WS-E (coaching canvas) |
| UX: dup goal, jargon, no practice path | WS-E (mechanical + `FocusRecord` loop) |
| Speed/cost of building all this | §7 |
