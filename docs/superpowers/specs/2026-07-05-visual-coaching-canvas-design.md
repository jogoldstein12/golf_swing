# Visual Coaching Canvas & Practice Loop — Design Spec

**Status:** Approved design (brainstormed 2026-07-05). Resolves the two design-gated items in `docs/superpowers/plans/2026-07-05-coaching-integrity-and-accuracy.md` (WS-E "takeaway-vs-video ordering" and "the practice loop shape") and expands WS-E from a mechanical card cleanup into an on-frame coaching feature. Feeds `superpowers:writing-plans`.

**Goal:** Turn the results screen's video/avatar into the *coaching surface* — draw where the swing goes wrong and what the corrected motion looks like *on the user's own frames* — and close the loop from a single diagnosis into a repeatable insight → drill → practice → re-check cycle across sessions.

**Architecture:** All app-side (`SwingThrough/`) plus one small coaching-content addition in `SwingKit`. Nothing in the canvas is invented: every overlay is drawn from data the pipeline already produces (`PlaneAnalysis`, checkpoints P1–P10, pose frames, metric ideal-ranges) or from the user's *own* prior swing. No synthetic "ideal body," ever.

**Tech Stack:** Swift 6 / SwiftUI, `SwingKit` SPM package, SwiftData (schema V3 for the pinned-focus record), XCTest + iPhone 17 Pro simulator UI tests.

---

## Why (evidence)

The 2026-07-05 research pass (three parallel agents: consumer apps, broadcast/biomechanics tooling, motor-learning science) converged on three points that agree across science *and* market:

1. **On-frame fault→fix beats text; overlay beats side-by-side.** External focus of attention (Wulf et al.) is the field's most-replicated finding: "rotate your shoulders" (internal/body cue) is the weak form; "swing the club into the corridor" (external/effect cue tied to a visible target) is the strong form. Independently, the app survey found the biggest market gap is exactly this — nearly every app prints a metric or a two-clip side-by-side; almost none draw *where* the error is and *what* the fix looks like, overlaid and time-synced.
2. **One cue for novices, depth on request.** Challenge-point / cognitive-load work: extra overlays measurably *slow* a beginner. "One prioritized fix" is now table-stakes UX. → progressive disclosure by skill.
3. **The honest reference is the user's own swing.** The powerful "ghost overlay" must not be a fabricated ideal (that violates the project's `PlausibilityGate` no-fabrication doctrine). Feedforward self-modeling — ghosting the user's *own best/prior* swing — is both honest and evidence-backed, and it doubles as the practice-loop payoff: next swing's ghost *is* last swing, so improvement is seen frame-on-frame. Video's benefit shows up at **retention across sessions**, not immediately → the carry-forward focus is the highest-value loop element.

Full findings and sources are in the conversation record; the four design decisions below are the distillation.

---

## Locked design decisions

| # | Decision | Choice |
|---|----------|--------|
| 1 | Target overlay reference | **Corridor by default; self-ghost once a clean prior same-club swing exists** |
| 2 | Screen order | **Quiet glance strip → coaching canvas → progressive depth** |
| 3 | Strip treatment | **Light/calm, score present but not shouted** |
| 4 | Practice loop | **Light: drill page + pinned carry-forward focus, verified next session** |

---

## Global constraints (inherited)

- **No fabricated measurements or references.** The corridor comes from a *known* ideal-plane band; the ghost is the user's *own* recorded swing. Never draw a synthesized ideal body or a line for a withheld (`.unavailable`) metric.
- **Withheld faults never get an overlay or a cue.** Consistent with WS-A: `report.coachableMetrics` (provenance ≠ `.unavailable`) gates what the canvas may draw. On an `insufficientData` report the canvas shows the raw video with no fault overlay, and the screen keeps today's `LowConfidenceLead`.
- **External-focus, prescriptive caption voice.** Every cue is an imperative about the *effect/target*, ≤ ~8 words ("Drop the club into the corridor"), never a body-part instruction.
- **Toolchain / determinism / commit conventions:** as in the coaching-integrity plan's Global Constraints.

---

## Components (units, responsibilities, interfaces)

### 1. `SwingOverlay` — the fault→drawing resolver  *(new, SwingKit or SwingThrough/Analysis)*
The one place that turns "this goal, this report" into "seek here, draw these primitives, say this."
- **Consumes:** a `CoachGoal` + the `SwingReport` (its `PlaneAnalysis`, `checkpoints`, `metrics`, `coachableMetrics`), plus an optional `priorReport` (for the ghost) and a `SkillLevel`.
- **Produces:** an `OverlayPlan`:
  - `position: SwingPosition` — the checkpoint to seek the scrubber to (e.g. P4/P5 for a plane fault). Resolved by metric family, mirroring `Drills.forLabel` keyword matching + `SwingComparison.metric(for:in:)`.
  - `primitives: [OverlayPrimitive]` — the honest drawing set. Cases: `.actualPlaneLine(angle:state:)`, `.targetCorridor(band:)`, `.heldReferenceLine(kind: .spine)`, `.pathTrace`, `.ghostClub(from: priorReport)`, `.moveArrow(from:to:)`.
  - `caption: String` — the external-focus cue (see §Coaching addition).
  - `layers: OverlayLayers` — which primitives are visible at the current disclosure level (novice = one line + corridor + caption; advanced adds reference line, path trace, and unlocks the kinematic-sequence panel).
- **Reference selection (Decision 1):** if a clean prior same-club/same-view swing exists whose relevant metric is `.measured`, emit `.ghostClub` + `.moveArrow`; else emit `.targetCorridor`. Corridor band derives from the metric's `ideal` range projected onto the plane geometry (`PlaneAnalysis.basePlaneAngle` + `deviationByPosition`). Never both at full strength — ghost supersedes corridor when present.
- **Depends on:** `PlaneAnalysis` (`basePlaneAngle`, `deviationByPosition`, `stateByPosition: [SwingPosition: PlaneState]`), `SwingPosition`, `PlaneState`, `MeasurementProvenance`.

### 2. `CoachingCanvas` — the drawing view  *(new, SwingThrough/Screens/Analysis)*
Renders an `OverlayPlan` on top of the existing hero panes. Reuses, does not replace, `VideoAnalysisView` and `AvatarPane`.
- **Responsibility:** given `OverlayPlan` + the current `AnalysisModel` (for `time`, `pane`, `selectedPosition`), draw the primitives as SwiftUI/Canvas shapes aligned to the frame; render the caption strip; host the `▶ See the fix`, drill pill, and the collapsed `▸ more lines` / `▸ power staircase` disclosure controls.
- **Interface:** `CoachingCanvas(model:, plan:, skill:)`. Purely presentational; owns no analysis logic.
- **"See the fix":** animates the scrubber from the fault frame toward the corridor/ghost (a scripted seek over `model.time`), giving the learner-requested reveal the research favors — not an always-on annotation.
- **Kinematic-sequence panel:** the advanced `▸ power staircase` expands an ordered pelvis→thorax→arm→club peak chart from `KinematicSequence.peaks`. Honest degeneracy note wired to WS-C's low-confidence flag (if the sequence is degenerate, the panel says so rather than drawing a confident staircase).

### 3. `GlanceStrip` — the top summary band  *(new, SwingThrough/Screens/Analysis)*
Decisions 2 + 3. A calm, light band at the very top: `score` (present, not loud) · one-line verdict / one-thing title · `▲ +N vs last`.
- **Interface:** `GlanceStrip(score:, oneThing:, scoreDelta:)`.
- Reuses `SwingComparison.scoreDelta`. On `insufficientData`, shows "Not scored — low-confidence read" instead of a number (no fabricated score).

### 4. `AnalysisScreen` re-order  *(modify, `SwingThrough/Screens/Analysis/AnalysisScreen.swift`)*
New top-to-bottom order: `header → GlanceStrip → CoachingCanvas (hero + scrubbers) → [MarkerDetail] → ScoreBlock → scoreDelta → measurement notes → Hairline → MetricsSection → goals → PracticeCTA`. The `LeadCard`'s "one thing" is absorbed into the canvas caption + `GlanceStrip`; `LeadCard` is retired for the scored path but `LowConfidenceLead` is kept for the insufficient path (surfaced where the canvas would be).

### 5. Practice loop  *(Decision 4)*
- **`DrillDetailScreen`** *(new, SwingThrough/Screens/Drills)*: opened by tapping a drill (from canvas pill, `GoalCard`, or `DrillsScreen`). Shows the external cue, `Drill.detail` method, a short "why it works," and one **"Work on this"** button.
- **`FocusRecord`** *(new @Model, SwiftData schema V3, lightweight migration)*: the pinned carry-forward focus — `club`, `viewRaw`, `goalTitle`, `metricLabel`, `cue`, `drillName`, `createdAt`, `resolvedSwingID: UUID?`. At most one active per (club, view). Adding a model → new `SwingThroughSchemaV3` + `MigrationStage.lightweight` (mirrors the existing V1→V2 pattern in `SwingSchema.swift`).
- **Home surfacing** *(modify, `HomeScreen.swift`)*: when an unresolved `FocusRecord` exists, a compact "Working on: {goalTitle} — record to check" card that routes into capture pre-set to that club/view.
- **Verify tie-in:** the next same-club/same-view swing runs the existing `SwingComparison.goalTrend` / `trend`; on `.fixed`/`.improving` the `FocusRecord` is marked resolved and the canvas ghost is that prior swing (loop closes visually). No new analysis math — reuses `SwingComparison` and the trend chip.

### 6. Mechanical WS-E fixes (folded in, unchanged from the plan)
De-dupe goal #1 (now moot once `LeadCard` is absorbed, but keep the guard in the goals `ForEach`), plain-language provenance ("Estimated" for `.inferred`/`.interpolated`, "Not measured" for `.unavailable`), and tappable drills → `DrillDetailScreen`.

---

## Coaching addition in SwingKit (connects to WS-A)

The caption needs an external-focus, prescriptive cue that neither coach emits today. Add `CoachGoal.cue: String?` — a short (≤ ~8-word) effect-focused imperative.
- **`RuleBasedCoach`:** maps each fault tier to a fixed external-focus cue (e.g. plane→"Drop the club into the corridor"; turn→"Turn your chest to the flag"). Deterministic, golden-testable.
- **`ClaudeCoach`:** system prompt gains a rule — every goal includes a `cue`: external focus (name the club/target/effect, never a body part), imperative, ≤ 8 words. Tool schema adds `cue` as required.
- **Honesty:** `cue` is advice phrasing, not a measurement — it carries no provenance and is only ever attached to a `coachableMetrics` goal. Withheld faults produce no goal, hence no cue, hence no overlay. This is additive to WS-A and does not change its acceptance criteria; it just gives the canvas its caption source.

---

## Data flow

`SwingReport` (has `PlaneAnalysis`, checkpoints, metrics, coaching goals w/ `cue`)
→ `AnalysisScreen` picks goal #1 (a `coachableMetrics` goal) + resolves `priorReport`
→ `SwingOverlay.plan(goal:, report:, prior:, skill:)` → `OverlayPlan`
→ `GlanceStrip` (score + one-thing + delta) and `CoachingCanvas` (seek to `plan.position`, draw `plan.primitives`, caption `plan.caption`)
→ user taps drill → `DrillDetailScreen` → "Work on this" writes a `FocusRecord`
→ `HomeScreen` shows the active focus → capture (pre-set club/view)
→ next report → `SwingComparison` trend resolves the `FocusRecord`, ghost = prior swing.

---

## Testing

- **`SwingOverlay` (SwingKit unit tests):** deterministic, headless. A steep-plane report → plan seeks P4/P5 and includes `.actualPlaneLine(state: .over)` + `.targetCorridor`. A withheld plane (`.unavailable`) → plan draws **no** plane primitive. With a clean prior swing present → plan swaps corridor for `.ghostClub` + `.moveArrow`. Novice skill → `layers` excludes reference line + path trace.
- **Coaching cue (SwingKit):** `RuleBasedCoach` emits a non-empty external-focus `cue` for each fault tier; golden payload updated; `CoachingPayloadEncoder` stays `Equatable`.
- **App UI tests (iPhone 17 Pro):** `GlanceStrip` shows score + "vs last"; tapping a drill navigates to `DrillDetailScreen`; "Work on this" then Home shows the active-focus card; the raw words "Inferred"/"Interpolated" never appear; `insufficientData` path shows the low-confidence lead and no fault overlay.
- **Snapshot/spot-check (advisory):** canvas overlay alignment on the bundled sample at P4 — visual, not a hard gate.

---

## Scope

**In (this cycle):** `SwingOverlay`, `CoachingCanvas` (plane corridor + held reference + path trace + self-ghost + external-focus caption + "See the fix" reveal + progressive disclosure), kinematic-sequence advanced panel (wired to WS-C's honesty flag), `GlanceStrip`, `AnalysisScreen` re-order, `DrillDetailScreen`, `FocusRecord` + Home surfacing + verify tie-in, `CoachGoal.cue`, and the mechanical WS-E fixes.

**Out (follow-on):**
- **Pro/model reference library** (ghost against a licensed tour swing) — needs licensing + careful "it's a model, not your ideal" framing.
- **Guided practice session** (rehearse→self-rate→check) and **rep-based/gamified** practice (green-when-right, streaks) — the heavier practice-node weights we explicitly deferred; both need live position-detection and risk the guidance-hypothesis dependency trap.
- **Path-vs-face impact arrows** and **multi-angle synthetic cameras** — the first needs reliable clubhead tracking; the second needs 3D reconstruction we don't have.
- Full longitudinal trends dashboard (a `vs last` delta + trend chip is in; a history graph is out).

---

## Multi-agent build workflow (speed + cost)

Consistent with the coaching-integrity plan's §7. This feature splits into lanes with mostly-disjoint files, run concurrently in worktree-isolated agents, each a TDD pipeline (failing test → implement → run tests → adversarial verify):
- **Lane V1 — `CoachGoal.cue` + coach cues** (SwingKit; small; `effort: low` for rule-map, `high` for the Claude prompt): unblocks captions.
- **Lane V2 — `SwingOverlay` resolver** (SwingKit; `effort: high`, correctness-critical): the honesty-sensitive core; **adversarial verifier loops until dry** trying to make a withheld/`.unavailable` metric produce an overlay primitive.
- **Lane V3 — `CoachingCanvas` + `GlanceStrip` + `AnalysisScreen` re-order** (app; `effort: medium`): depends on V2's `OverlayPlan` interface — starts against the typed interface, integrates when V2 lands.
- **Lane V4 — practice loop: `FocusRecord`/schema V3, `DrillDetailScreen`, Home surfacing** (app; `effort: medium`): disjoint from V3's files.
- **Lane V5 — mechanical WS-E fixes** (app; `effort: low`).
Integration barrier: full `swift test --package-path SwingKit` + simulator scheme green before merge; human reviews each lane's diff at the two-stage gate. Model/effort tiered so mechanical lanes don't pay for high-reasoning tokens; verifier fan-out scales with any `+Nk` budget (2 for critical lanes V1/V2, 1 elsewhere). Never merge a critical lane a verifier couldn't clear.

---

## Open items (resolve during writing-plans / build)

1. **Overlay geometry calibration** — projecting the metric ideal-range into an on-frame corridor needs the address plane geometry; validate alignment against the bundled DTL sample and keep the projection constants named, not literal (ties to WS-D's fixture).
2. **Face-on view** — `PlaneAnalysis` is DTL-oriented (`Basis` is nil for face-on). For face-on swings the canvas draws the held reference line + turn cues but not the plane corridor; confirm the face-on overlay set during V2.
3. **Ghost alignment** — the self-ghost must be time-synced to the same checkpoint (P4 to P4), not the same clock time; reuse checkpoint times, not raw `time`.
4. **`CoachGoal.cue` optionality** — old reports won't have it; canvas falls back to a neutral cue derived from `goal.title` when `cue == nil` (no schema bump needed — additive Codable field).
