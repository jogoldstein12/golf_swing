# Swing Through — features (benchmarked against Sparrow & Sportsbox 3D)

## What the best apps do (researched)

**Sparrow Golf**
- Auto-detects the swing in real time — no "press record".
- 30+ points of analysis depending on swing type; grounded in swing biomechanics.
- Real-time biomechanical feedback (spine angle, alignments, excessive knee bend…).
- **SparrowScore** that trends up as you improve; stored swing history.
- Side-by-side comparison vs PGA pros with overlaid analysis lines.
- Extensive drill-video library tied to your faults.

**Sportsbox 3D Golf**
- Single-camera → full **3D avatar** + 3D kinematic data (no markers/sensors).
- Six degrees of freedom for pelvis & chest: turn, bend, side bend, sway, lift/drop,
  thrust — all referenced to address.
- Torso/pelvis rotation, hip sway & thrust, shoulder/arm angles, tempo, **sequence**,
  center-of-mass, posture — measured in 3D.
- ~2° accuracy vs electromagnetic gold-standard (with good camera setup).
- Progress tracking; guided camera setup for accuracy.

## Swing Through — our feature set

### v1 (prototype focus)
- **Dual view:** the user's **video** and the **3D clay figure** — equal billing, toggle
  or split. See yourself *and* the model.
- **Swing-plane overlay on the actual video:** base plane line, actual shaft path, and a
  fault band — on-plane (green) / over-the-top (amber, above) / under-plane (below) —
  with a magnitude callout. Plus spine, hip, and shoulder lines, and tracked joint /
  contact points on the body.
- **Checkpoint scrubber:** Address · Top · Impact · Follow (full P1–P10 later).
- **Metrics with ideal bands:** swing plane, tempo, shoulder turn, hip turn, spine angle,
  sway — each shown against its optimal range.
- **Swing Score** (0–100) from the swing model, weighted toward sequence & plane.
- **Coaching notes:** specific, prioritized (earliest fault in the chain first) + a drill.

### v2+
- Real-time capture with auto swing-detection and framing/lighting guidance.
- Multiple angles from one phone (down-the-line + face-on), fused into one report.
- 6-DOF pelvis/chest tracking on the 3D figure; kinematic-sequence graph.
- Pro comparison overlay; progress trends; drill library keyed to detected faults.
- Native SwiftUI build (Apple Vision on-device pose) via the master Fable prompt.

## Technical approach (accuracy-first)
Pose estimation (in-browser MediaPipe now; Apple Vision on native) → 3D joint tracks →
biomechanics per `SWING_MODEL.md` → scored metrics → overlays on video + 3D figure →
coaching layer grounded in the swing model. Numbers come from measurement, not from
asking a vision model to eyeball the video.
