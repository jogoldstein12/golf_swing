// Per-checkpoint swing data for the video (down-the-line) view: tracked 2D skeletons,
// interactive good/fault markers, plus the derived Goals and coaching notes. Grounded in
// docs/SWING_MODEL.md. In the real pipeline these come from pose-estimation joint tracks;
// here they are authored per checkpoint so the scrubber, markers, and coaching are live.

export type Vec2 = [number, number]
export type Checkpoint = 'Address' | 'Top' | 'Impact' | 'Follow'
export const CHECKPOINTS: Checkpoint[] = ['Address', 'Top', 'Impact', 'Follow']

export type Marker = {
  id: string
  at: string // joint key
  kind: 'good' | 'fault'
  title: string
  detail: string
}

export type Skeleton = {
  joints: Record<string, Vec2>
  club: [string, Vec2] // [handsJointKey, clubheadPoint]
  markers: Marker[]
  planeState: 'on' | 'over' | 'under' | 'none'
  label: string
}

export const BONES2D: [string, string][] = [
  ['footL', 'kneeL'], ['kneeL', 'hipL'], ['footR', 'kneeR'], ['kneeR', 'hipR'],
  ['hipL', 'pelvis'], ['hipR', 'pelvis'], ['pelvis', 'chest'], ['chest', 'shoulderL'],
  ['chest', 'shoulderR'], ['shoulderL', 'shoulderR'], ['chest', 'neck'], ['neck', 'head'],
  ['shoulderL', 'elbowL'], ['elbowL', 'hands'], ['shoulderR', 'elbowR'], ['elbowR', 'hands'],
]

// Ideal base plane, shared reference across checkpoints (down-the-line).
export const PLANE_LINE = { x1: 150, y1: 324, x2: 278, y2: 140 }

export const SKELETONS: Record<Checkpoint, Skeleton> = {
  Address: {
    label: 'Address · P1',
    planeState: 'none',
    joints: {
      footL: [150, 320], footR: [184, 315], kneeL: [154, 263], kneeR: [185, 261],
      hipL: [165, 209], hipR: [192, 210], pelvis: [179, 209], chest: [176, 150],
      shoulderL: [168, 141], shoulderR: [193, 141], neck: [182, 132], head: [186, 113],
      elbowL: [166, 190], elbowR: [189, 191], hands: [170, 234],
    },
    club: ['hands', [150, 322]],
    markers: [
      { id: 'a1', at: 'chest', kind: 'good', title: 'Athletic posture', detail: 'Spine tilt of 34° from vertical — a neutral, powerful setup. Weight balanced over the arches.' },
      { id: 'a2', at: 'hands', kind: 'good', title: 'Neutral hand position', detail: 'Hands sit just inside the lead thigh, shaft in line with the lead arm. Good starting point for an on-plane takeaway.' },
    ],
  },
  Top: {
    label: 'Top · P4',
    planeState: 'over',
    joints: {
      footL: [150, 320], footR: [184, 315], kneeL: [156, 263], kneeR: [186, 261],
      hipL: [166, 209], hipR: [193, 211], pelvis: [180, 210], chest: [176, 151],
      shoulderL: [171, 139], shoulderR: [197, 132], neck: [184, 128], head: [189, 109],
      elbowL: [195, 116], elbowR: [215, 121], hands: [215, 96],
    },
    club: ['hands', [263, 77]],
    markers: [
      { id: 't1', at: 'hands', kind: 'fault', title: 'Over the top', detail: 'At the top the club works above your base plane — shaft ~4.2° steep. From here it will drop out-to-in, the classic cause of pulls and slices.' },
      { id: 't2', at: 'shoulderR', kind: 'good', title: 'Full shoulder turn', detail: '92° of shoulder rotation against 46° of hip turn — strong coil and separation. Power is there; it just needs to be delivered on plane.' },
    ],
  },
  Impact: {
    label: 'Impact · P7',
    planeState: 'on',
    joints: {
      footL: [150, 320], footR: [186, 312], kneeL: [156, 263], kneeR: [190, 258],
      hipL: [164, 207], hipR: [197, 205], pelvis: [181, 207], chest: [177, 150],
      shoulderL: [172, 142], shoulderR: [197, 143], neck: [184, 133], head: [187, 114],
      elbowL: [170, 192], elbowR: [192, 190], hands: [178, 236],
    },
    club: ['hands', [151, 322]],
    markers: [
      { id: 'i1', at: 'hands', kind: 'good', title: 'Shaft lean', detail: 'Hands lead the clubhead into the ball with forward shaft lean — compresses the ball and de-lofts through impact.' },
      { id: 'i2', at: 'hipR', kind: 'fault', title: 'Early extension', detail: 'The pelvis has thrust ~2 in toward the ball, standing you up slightly. This steepens the shaft and forces compensations through impact.' },
    ],
  },
  Follow: {
    label: 'Follow-through · P10',
    planeState: 'none',
    joints: {
      footL: [152, 320], footR: [180, 300], kneeL: [158, 262], kneeR: [182, 256],
      hipL: [168, 206], hipR: [190, 205], pelvis: [180, 206], chest: [176, 148],
      shoulderL: [170, 138], shoulderR: [194, 136], neck: [180, 128], head: [180, 108],
      elbowL: [150, 118], elbowR: [166, 112], hands: [150, 128],
    },
    club: ['hands', [112, 92]],
    markers: [
      { id: 'f1', at: 'chest', kind: 'good', title: 'Balanced finish', detail: 'Chest faces the target, weight fully onto the lead side, trail foot released. A stable, repeatable finish.' },
    ],
  },
}

export type Goal = {
  title: string
  detail: string
  metric: string
  current: string
  target: string
  drill: string
  priority: number
}

// Coaching, grounded in the swing model: fix the earliest link in the chain first
// (sequence & plane before cosmetics). Ordered by priority.
export const GOALS: Goal[] = [
  {
    priority: 1,
    title: 'Shallow the shaft in transition',
    detail:
      'Your one swing-changer. Feel the trail elbow lead down in front of the hip as the pelvis opens — this drops the club under your steep line and delivers it on plane, squaring the face sooner.',
    metric: 'Swing plane at P5',
    current: '+4.2° steep',
    target: '±1.5°',
    drill: 'Pump drill — pause at the top, drop hands to trail pocket, then fire.',
  },
  {
    priority: 2,
    title: 'Sequence hips before arms',
    detail:
      'The downswing should unload from the ground up: pelvis, then torso, then arms, then club. Right now the arms fire a touch early — sequencing them last recovers speed and consistency.',
    metric: 'Kinematic sequence',
    current: 'Arms early',
    target: 'Pelvis-led',
    drill: 'Step-change drill — small lead-foot step to start the downswing.',
  },
  {
    priority: 3,
    title: 'Hold your spine angle',
    detail:
      'Keep the pelvis back through impact instead of thrusting toward the ball. Maintaining posture keeps the low point consistent and takes the steepness out of the strike.',
    metric: 'Chest thrust at P7',
    current: '+2.0 in',
    target: '±0.5 in',
    drill: 'Chair drill — brush your seat against a chair back through impact.',
  },
]
