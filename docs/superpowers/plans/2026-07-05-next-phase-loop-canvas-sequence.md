# Next Phase — Close the Loop, Align the Canvas, Show the Power Sequence

> **For agentic workers:** self-contained spec, three independent workstreams (NP-1/2/3), each individually shippable with its own acceptance criteria + TDD anchors. Builds directly on the merged coaching-canvas work (PR #2). Implement via `superpowers:subagent-driven-development`; TDD (failing test → minimal fix → green → commit).

**Goal:** Finish the practice loop we shipped half of (pin → **verify/resolve**), make the coaching canvas draw on the *actual* video frame instead of a schematic, and surface the one biomechanics visual we already have the data for — the kinematic-sequence "staircase" — honestly gated.

**Architecture:** NP-1 is data/state (SwiftData + a pure resolver), NP-2 is canvas geometry (a pure image→screen mapping + an overlay split), NP-3 is a new honest-gated chart plus one shared SwingKit predicate. All three lean on code that already exists; none invents a new measurement.

**Tech Stack:** Swift 6 / SwiftUI, `SwingKit` SPM package, SwiftData, XCTest + iPhone 17 Pro simulator.

## Global Constraints (inherited)

- **Toolchain:** `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `swift test --package-path SwingKit`; `xcodegen generate` then `xcodebuild -scheme SwingThrough -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.
- **No fabrication.** No line is drawn from a value the pipeline withheld; no plane line when `basePlaneLine2D == nil`; no confident sequence order when the read is low-confidence. Honest fallback (draw nothing / grey with a note) always beats a guess.
- **Determinism** preserved; pure helpers (`FocusResolver`, `CanvasGeometry`, `KinematicSequence.isDegenerate`) are headless-unit-tested.
- **Backward-compatible SwiftData.** NP-1 adds no new stored fields (it only *writes* `FocusRecord.resolvedSwingID`, already in SchemaV3) → no migration.
- **TDD + one workstream per commit**, conventional-commit + `Co-Authored-By: Claude Opus 4.8 (1M context)` trailer.

---

## NP-1 — Close the practice loop: verify & resolve the pinned focus

**Problem:** `DrillDetailScreen` pins a `FocusRecord` and `HomeScreen` surfaces it, but nothing ever resolves it — the "Working on" card is one-way and persists forever. The cross-session retention mechanic the whole design rests on is unfinished.

**Files:**
- New: `SwingThrough/Store/FocusResolver.swift` (pure decision + the SwiftData write).
- Modify: `SwingThrough/Screens/Analyze/SwingSession.swift` (call the resolver after `context.insert(record)` ~line 374, with `context` + `history` in scope).
- Modify: `SwingThrough/Screens/Home/HomeScreen.swift` (a lightweight "just fixed" surface for a recently-resolved focus).
- Test: `SwingThroughTests/FocusResolverTests.swift`.

**Decisions (filled):**
- Pure predicate: `FocusResolver.shouldResolve(focus: FocusRecord, history: [SwingReport], current: SwingReport) -> Bool` = `SwingComparison.trend(for: focus.metricLabel, history: history) == .fixed`. `.improving` keeps the focus **active** (progress, not done); `.fixed` (two consecutive measured swings in band, per `SwingComparison.fixedStreak`) resolves it. A withheld metric on the new swing never resolves (SwingComparison already refuses to difference un-measured values).
- Side-effecting entry point: `FocusResolver.resolve(newReport:record:history:context:)` — finds the unresolved `FocusRecord` matching `(club, viewRaw)`, builds the same-club/same-view report history (reuse the `SwingComparison.trendWindow` slice, loading reports via `SwingStore.loadReport`), and if `shouldResolve` sets `focus.resolvedSwingID = record.id` + saves. No-op when there's no matching active focus.
- Ghost tie-in needs **no** new code: `AnalysisScreen` already passes `priorReport` (nearest prior clean same-club/same-view swing) into `SwingOverlay.plan`, which already ghosts it. The pinned focus and the ghost are naturally the same swing family; NP-1 doesn't touch the overlay.
- Home surface: when a focus resolved within the last N swings (or simply `isResolved && resolvedSwingID == latest.id`), show a one-line "Fixed: {goalTitle}" chip in place of the working-on card for that session, then it falls away. Keep it minimal — the working-on card clearing is the required behavior; the chip is polish.

**Acceptance criteria:**
- [ ] `shouldResolve` is true iff the metric trend is `.fixed`; `.improving`/`.regressing`/`.insufficient` → false (headless unit test).
- [ ] After a same-club/same-view swing whose focus metric reaches `.fixed`, the matching `FocusRecord.resolvedSwingID` is set and the Home "Working on" card clears.
- [ ] A focus never resolves off a different club/view, nor off a swing where the metric is withheld.

```swift
// FocusResolverTests (pure, headless)
func testFixedTrendResolves() {
    let focus = FocusRecord(club: "7 Iron", viewRaw: CaptureView.downTheLine.rawValue,
                            goalTitle: "Shallow the shaft", metricLabel: "Swing Plane",
                            cue: "Drop the club into the corridor", drillName: "Pump drill")
    let history = /* two consecutive in-band Swing Plane reports */
    XCTAssertTrue(FocusResolver.shouldResolve(focus: focus, history: history, current: history.last!))
}
func testImprovingButNotFixedStaysActive() { /* out→in once ⇒ false */ }
```

---

## NP-2 — Video-align the canvas overlay

**Problem:** `CoachingCanvas` draws its plane geometry schematically, anchored to a synthetic ball point — a diagram *beside* the swing, not the fix *on your frame*. We already compute `PlaneAnalysis.basePlaneLine2D` (normalized image-space `[ground/ball end, upper end]`) and `report.videoWidth/videoHeight`.

**Files:**
- New: `SwingThrough/Screens/Analysis/CanvasGeometry.swift` (pure image→screen mapping) + `PlaneOverlay` view (the lines, drawn in video space).
- Modify: `SwingThrough/Screens/Analysis/CoachingCanvas.swift` — split into `PlaneOverlay` (lines) + the existing caption/controls band; the band stays below the hero, the overlay moves *into* the hero ZStack over `VideoAnalysisView`.
- Modify: `SwingThrough/Screens/Analysis/AnalysisScreen.swift` — place `PlaneOverlay` inside `heroCard`'s `ZStack`, pass the plan; keep the caption/controls band where the canvas is today.
- Test: `SwingThroughTests/CanvasGeometryTests.swift`.

**Decisions (filled):**
- Pure mapping: `CanvasGeometry.imagePoint(_ normalized: CGPoint, videoSize: CGSize, in rect: CGRect) -> CGPoint` implements **aspect-fit** (the mode `VideoAnalysisView` uses): compute the letterboxed video rect inside `rect`, then map normalized `[0,1]` image coords into it. All overlay geometry maps through this one function so lines land on the pixels.
- Anchor + angles: the ball anchor is `basePlaneLine2D[0]` (mapped). The **actual** plane line is drawn from the anchor at `basePlaneAngle + metricValue` degrees; the **corridor** is the wedge between `basePlaneAngle + idealLow` and `+ idealHigh`; the **ghost** is drawn from the *same current anchor* at the prior swing's `basePlaneAngle + priorValue` (its angle shown on your current frame — honest, and avoids cross-clip pixel registration).
- Honest fallback: when `basePlaneLine2D == nil` (shaft not measured, or face-on) → draw **no** plane line/corridor; the caption + controls still render. (Face-on's own overlay set is out of scope here.)
- Degrade with provenance: an `.inferred` plane still draws but dashed/amber (matches the "Estimated" tag); `.unavailable` never reaches here (SwingOverlay already gates it).

**Acceptance criteria:**
- [ ] `imagePoint` maps corners correctly under aspect-fit for portrait and landscape video in a differently-shaped rect (letterbox math), headless.
- [ ] With `basePlaneLine2D` + video size present, the actual-plane line's anchor equals `imagePoint(basePlaneLine2D[0], …)` within 1pt.
- [ ] `basePlaneLine2D == nil` → `PlaneOverlay` renders no plane line (only the caption/controls survive).
- [ ] Overlay never draws outside the mapped video rect (clipped).

```swift
func testAspectFitMapsBallAnchorOntoLetterboxedRect() {
    // 1080x1920 video shown in a 300x300 rect → vertical letterbox; a normalized
    // point maps inside the fitted sub-rect, not the full 300x300.
    let p = CanvasGeometry.imagePoint(CGPoint(x: 0.5, y: 1.0),
                                      videoSize: CGSize(width: 1080, height: 1920),
                                      in: CGRect(x: 0, y: 0, width: 300, height: 300))
    XCTAssertEqual(p.x, 150, accuracy: 0.5)
    XCTAssertTrue(p.y <= 300)
}
```

---

## NP-3 — Kinematic-sequence "staircase" panel (honest-gated)

**Problem:** the strongest power-diagnosis visual in the research, and we already compute `KinematicSequence.series` (per-segment deg/s traces) + `times`, but never show it. The `▸ more lines` disclosure and the mockup's "power staircase" hook exist; the chart doesn't.

**Files:**
- Modify: `SwingKit/Sources/SwingKit/Report.swift` — add public `KinematicSequence.isDegenerate` (pelvis/torso peaks within one frame) so the app and the score share **one** definition of degeneracy.
- Modify: `SwingKit/Sources/SwingKit/Pipeline/MetricsBuilder.swift` — `score()`/`isSequenceDegenerate` delegate to the new shared predicate (no behavior change; single source of truth).
- New: `SwingThrough/Screens/Analysis/SequenceStaircase.swift` — a `Canvas` chart of the four color-coded curves + peak markers; a `SequencePresentation.isTrustworthy(_:) -> Bool` gate.
- Modify: `SwingThrough/Screens/Analysis/AnalysisScreen.swift` — a collapsible "Power sequence" section below `MetricsSection`.
- Test: `SwingKit/Tests/SwingKitTests/KinematicSequenceTests.swift` (+`isDegenerate`); `SwingThroughTests/SequencePresentationTests.swift`.

**Decisions (filled):**
- `KinematicSequence.isDegenerate` = pelvis and torso peaks within `0.033s` (the same window WS-C's `MetricsBuilder.sequenceDegenerateWindow` uses — move the constant onto `KinematicSequence` and have `MetricsBuilder` reference it, keeping one number).
- Trust gate: `SequencePresentation.isTrustworthy(_ seq:) = seq.peaks.count == 4 && seq.lowConfidence != true && !seq.isDegenerate`. When **untrustworthy**, the chart still draws the traces but **greyed**, with an honest caption ("Body rotation was too unsteady at the top to judge the order") — never the confident ascending "staircase" claim or a green in-order tick.
- Placement + disclosure: a collapsible `FloatCard` "Power sequence" below the metrics, collapsed by default (it's depth, not the novice's one cue — consistent with the challenge-point principle). No new skill plumbing required for this panel; it's opt-in by tapping.
- Honesty of the visual itself: peak markers labelled with segment + time; the "in order / ascending" verdict shown **only** when trustworthy.

**Acceptance criteria:**
- [ ] `KinematicSequence.isDegenerate` true for pelvis/torso 8ms apart, false at 50ms apart (SwingKit unit test); `MetricsBuilder` uses the shared predicate and WS-C's `ScoreReliabilityTests` still pass.
- [ ] `SequencePresentation.isTrustworthy` is false when `lowConfidence == true` OR degenerate OR `peaks.count != 4` (headless).
- [ ] The panel renders for a clean sequence with an "in order" verdict; for the bundled degenerate demo it renders greyed with the caution and **no** confident-order claim (UI test asserts the caution text / absence of an "in order" affordance).

```swift
// SwingKit
func testDegeneratePredicateSharedWithScore() {
    let degen = KinematicSequence(peaks: peaksAt(pelvis: 1.000, torso: 1.008, arm: 1.10, club: 1.15))
    XCTAssertTrue(degen.isDegenerate)
    XCTAssertTrue(MetricsBuilder.isSequenceDegenerate(degen))   // same answer
}
```

---

## §Sequencing, risks, self-review

**Sequencing:** NP-1 (data/state) and NP-3 (chart) are fully independent and can run in parallel. NP-2 (canvas geometry) and NP-3 both add to `AnalysisScreen` — land NP-2's hero-overlay change first, then NP-3's section, or coordinate the two `AnalysisScreen` edits in one lane. Each lane ends by running `swift test --package-path SwingKit` + the simulator UI suite before merge (per the shipped WS-E gate).

**Risks:**
- NP-2 alignment depends on `VideoAnalysisView`'s exact fit mode; confirm it is aspect-fit (not fill) before trusting the mapping, and calibrate against `DemoData` (which has `basePlaneLine2D` + `basePlaneAngle`) and the WS-D fixture. If the video is drawn aspect-fill, swap the letterbox math for crop math in the one `CanvasGeometry` function.
- NP-1 resolution runs off `SwingStore.loadReport` history; guard the sample/`isSample` case and missing reports (skip, don't crash).
- NP-3 sharing the degeneracy constant must not shift WS-C scoring — assert `ScoreReliabilityTests` stays green.

**Coverage:**

| Recommendation | Workstream |
|---|---|
| Close the practice loop's verify step | NP-1 |
| Video-align the canvas overlay (on-frame, not schematic) | NP-2 |
| Kinematic-sequence staircase, honestly gated | NP-3 |

**Out (still deferred):** face-on overlay set, skill-level personalization + faded feedback, pro/model reference ghost, live-capture guidance, and a live-model eval harness for WS-A's Claude path — all named in the phase-1 spec's roadmap and unchanged here.
