import * as THREE from 'three'

export type Vec3 = [number, number, number]

// A right-handed golfer at address, ball in front (+z). Units ≈ metres, figure ≈ 1.6m.
// Hand-authored so the biomechanics read true; refined against rendered frames.
export const JOINTS: Record<string, Vec3> = {
  ankleL: [-0.15, 0.0, 0.0],
  ankleR: [0.15, 0.0, 0.02],
  kneeL: [-0.14, 0.46, 0.07],
  kneeR: [0.14, 0.46, 0.07],
  hipL: [-0.13, 0.9, -0.04],
  hipR: [0.13, 0.9, -0.04],
  pelvis: [0.0, 0.91, -0.05],
  chest: [0.0, 1.28, 0.05],
  neck: [0.0, 1.41, 0.07],
  head: [0.0, 1.56, 0.08],
  shoulderL: [-0.19, 1.35, 0.05],
  shoulderR: [0.19, 1.35, 0.05],
  elbowL: [-0.16, 1.07, 0.19],
  elbowR: [0.16, 1.07, 0.19],
  hands: [0.0, 0.83, 0.31],
}

// Per-segment thickness so the figure reads as a sculpted mannequin, not a stick.
export function boneRadius(a: string, b: string): number {
  const s = new Set([a, b])
  if (s.has('pelvis') && s.has('chest')) return 0.085
  if (s.has('hipL') && s.has('hipR')) return 0.07
  if (s.has('shoulderL') && s.has('shoulderR')) return 0.055
  if ((s.has('hipL') || s.has('hipR')) && (s.has('kneeL') || s.has('kneeR'))) return 0.058
  if ((s.has('kneeL') || s.has('kneeR')) && (s.has('ankleL') || s.has('ankleR'))) return 0.046
  if (s.has('shoulderL') || s.has('shoulderR')) return 0.04
  if (s.has('elbowL') || s.has('elbowR')) return 0.033
  if (s.has('neck')) return 0.035
  return 0.04
}

export const BONES: [string, string][] = [
  ['ankleL', 'kneeL'],
  ['kneeL', 'hipL'],
  ['ankleR', 'kneeR'],
  ['kneeR', 'hipR'],
  ['hipL', 'pelvis'],
  ['hipR', 'pelvis'],
  ['hipL', 'hipR'],
  ['pelvis', 'chest'],
  ['chest', 'shoulderL'],
  ['chest', 'shoulderR'],
  ['shoulderL', 'shoulderR'],
  ['shoulderL', 'elbowL'],
  ['elbowL', 'hands'],
  ['shoulderR', 'elbowR'],
  ['elbowR', 'hands'],
  ['chest', 'neck'],
  ['neck', 'head'],
]

export const BALL: Vec3 = [0.0, 0.035, 0.46]

// Swing plane: a tilted disc passing through the ball and the trail shoulder.
// Described by a normal; the clubhead path is an arc lying in this plane.
// The clubhead path as an explicit swing arc: ball (impact) sweeping up and behind
// the trail shoulder to the top of the backswing. Control points read as a true
// down-the-line swing regardless of camera.
export const SWING_KEYS: Vec3[] = [
  [0.0, 0.03, 0.44], // impact / ball
  [0.5, 0.5, 0.12], // early backswing, trail side
  [0.62, 1.02, -0.16], // three-quarter
  [0.34, 1.66, -0.36], // top of backswing, high behind trail shoulder
]

export function swingPath(samples = 96): THREE.Vector3[] {
  const curve = new THREE.CatmullRomCurve3(SWING_KEYS.map((p) => new THREE.Vector3(...p)))
  return curve.getPoints(samples)
}

export type Metric = {
  label: string
  value: string
  unit?: string
  fill: number // 0..1 position on the meter
  band: [number, number] // ideal band as fractions 0..1
}

export const SWING_SCORE = 86

export const METRICS: Metric[] = [
  { label: 'Swing Plane', value: '61', unit: '°', fill: 0.72, band: [0.58, 0.8] },
  { label: 'Tempo', value: '3.1', unit: ':1', fill: 0.66, band: [0.6, 0.75] },
  { label: 'Shoulder Turn', value: '92', unit: '°', fill: 0.84, band: [0.78, 0.95] },
  { label: 'Hip Turn', value: '46', unit: '°', fill: 0.55, band: [0.5, 0.7] },
  { label: 'Spine Angle', value: '34', unit: '°', fill: 0.48, band: [0.42, 0.6] },
]
