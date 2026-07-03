# The Swing Model — how a golf swing should be optimized

This is Swing Through's ground truth. Every metric, overlay, score, and coaching note is
derived from these principles. It is the reference the coaching layer is grounded in so
feedback is *specific and correct*, not generic. Sources: TPI biomechanics, Sportsbox AI
6-degrees-of-freedom framework, published kinematic-sequence research, and standard
down-the-line / face-on video-analysis practice.

## 1. The kinematic sequence (the single most important thing)

An efficient downswing unloads from the ground up, each segment peaking **in order**:

    pelvis  →  torso/thorax  →  lead arm  →  club

Each distal segment reaches peak angular velocity *after* its proximal driver, and
decelerates to pass energy on (summation of speed). Elite reference peaks roughly:
pelvis first, then thorax, then arm, then club — the *timing offsets* matter as much as
the magnitudes. Faults: arms/club firing early ("casting", over-the-top), or pelvis and
torso peaking together (no separation → leaked speed, inconsistent face).

**We measure:** peak-speed order + the transition sequence. A correct order is the
backbone of the Swing Score.

## 2. Swing plane (the fault the user most wants to see)

Down-the-line, draw the **base plane line** from the ball through the hands/shaft at
address, extended up. The club should return through the "V" between the shaft plane and
the trail-forearm plane.

- **On plane:** shaft tracks the V into impact. Neutral path.
- **Over the top (steep / out-to-in):** in transition the club works *above/outside* the
  base plane, then swings left through impact. Causes pulls and slices. The classic amateur
  fault. Signature: clubhead outside the hands early in the downswing.
- **Under plane (shallow / in-to-out):** club drops *below* the base plane, swings right.
  Causes blocks and hooks. Signature: clubhead trapped behind the body.

**We detect + overlay:** base plane, actual shaft path, and the deviation band, colored
by fault (on-plane = fairway green, over-the-top = amber/red above the line, under =
below the line). Reported with a magnitude (e.g. "shaft 4.2° steep at P5").

## 3. The six degrees of freedom (per pelvis and chest) — Sportsbox framework

Three linear, three angular movements, all referenced to address (0 at setup):

| DOF | Axis | Optimal tendency | Common fault |
|---|---|---|---|
| **Turn** | rotation (yaw) | Full shoulder turn ~90°, hips ~45° at top | Under-turn → loss of power |
| **Bend** | forward/back tilt | Maintain spine bend to the ball | Early extension (standing up) |
| **Side bend** | lateral tilt | Trail-side tilt through impact | Reverse spine at top |
| **Sway** | left/right (linear) | Small; centered pivot | Excessive sway off the ball |
| **Lift / Drop** | up/down (linear) | Slight drop into transition | Big lift → thin/fat contact |
| **Thrust** | toward/away ball (linear) | Stable; chest holds distance | Thrust toward ball → early extension |

## 4. Positions we key on (the swing "checkpoints")

Address (P1), Takeaway (P2), Lead arm parallel (P3), **Top (P4)**, Transition (P5),
Delivery (P6), **Impact (P7)**, Follow-through (P8→P10). We surface Address / Top /
Impact / Follow by default and let the user scrub the full sequence.

## 5. Tempo

Backswing-to-downswing time ratio. Tour benchmark ≈ **3:1** (e.g. 0.75s back / 0.25s
down). We measure it from frame timing and flag deviations, since rushed transition is a
top cause of sequence breakdown.

## 6. Core static/postural checks

- **Spine angle** maintained from address to impact (early extension is a red flag).
- **Head / sternum stability** (sway box) — minimal lateral drift off the ball.
- **Hip & shoulder lines** — tilt and rotation at each checkpoint.
- **Knee flex** preserved; avoid excessive stand-up.
- **Weight transfer / pressure** shifting to lead side through impact.

## 7. How this drives the app

1. Pose estimation → 3D joint tracks per frame (see FEATURES.md).
2. Derive the metrics above per checkpoint → hard numbers.
3. Score against optimal bands → Swing Score + per-metric meters.
4. Overlay faults on the user's **video** (plane, lines, contact points) and mirror on the
   **3D clay figure**.
5. The coaching layer reads the numbers + this model → specific, prioritized notes and
   drills (fix the *earliest* link in the chain first: sequence/plane before cosmetics).
