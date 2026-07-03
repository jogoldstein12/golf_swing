// Swing-plane + skeletal-tracking overlay as it renders on the user's recorded video
// (down-the-line, top of backswing). Here it sits on a capture stand-in; the overlay
// engine is the deliverable — feed pose-estimation joint tracks in and these come live.

const INK = '#191712'
const FAIRWAY = '#7FA80C'
const AMBER = '#DB851F'

// Down-the-line golfer at the top of the backswing.
const J: Record<string, [number, number]> = {
  ball: [150, 324],
  footL: [150, 320],
  footR: [184, 315],
  kneeL: [156, 263],
  kneeR: [186, 261],
  hipL: [166, 209],
  hipR: [193, 211],
  pelvis: [180, 210],
  chest: [176, 151],
  shoulderL: [171, 139],
  shoulderR: [197, 132],
  neck: [184, 128],
  head: [189, 109],
  elbowL: [195, 116],
  elbowR: [215, 121],
  hands: [215, 96],
  clubhead: [263, 77],
}
const BONES: [string, string][] = [
  ['footL', 'kneeL'], ['kneeL', 'hipL'], ['footR', 'kneeR'], ['kneeR', 'hipR'],
  ['hipL', 'pelvis'], ['hipR', 'pelvis'], ['pelvis', 'chest'], ['chest', 'shoulderL'],
  ['chest', 'shoulderR'], ['shoulderL', 'shoulderR'], ['chest', 'neck'], ['neck', 'head'],
  ['shoulderL', 'elbowL'], ['elbowL', 'hands'], ['shoulderR', 'elbowR'], ['elbowR', 'hands'],
]
const DOTS = ['shoulderL', 'shoulderR', 'hands', 'hipL', 'hipR', 'kneeL', 'kneeR']
const p = (k: string) => J[k]

export default function VideoAnalysis() {
  return (
    <svg viewBox="0 0 390 360" className="h-full w-full" preserveAspectRatio="xMidYMid slice">
      <defs>
        <linearGradient id="cap" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#E7E3D9" />
          <stop offset="0.78" stopColor="#DCD5C6" />
          <stop offset="0.78" stopColor="#CFC8B2" />
          <stop offset="1" stopColor="#C6BEA5" />
        </linearGradient>
        <radialGradient id="vig" cx="0.42" cy="0.4" r="0.8">
          <stop offset="0.55" stopColor="#000" stopOpacity="0" />
          <stop offset="1" stopColor="#000" stopOpacity="0.09" />
        </radialGradient>
      </defs>

      {/* Capture backdrop (stand-in for the user's recorded frame) */}
      <rect width="390" height="360" fill="url(#cap)" />

      {/* Ideal base swing plane (ball → up through the hands, extended) */}
      <line x1={p('ball')[0]} y1={p('ball')[1]} x2="278" y2="140" stroke={FAIRWAY} strokeWidth="1.8" strokeDasharray="1 6" strokeLinecap="round" />

      {/* Plane-gap indicator: club sits above the plane = over the top */}
      <line x1={p('clubhead')[0]} y1={p('clubhead')[1]} x2={p('clubhead')[0]} y2="156" stroke={AMBER} strokeWidth="1.4" strokeDasharray="3 3" />
      <text x={p('clubhead')[0] + 6} y="120" fontFamily="Hubot Sans Variable, sans-serif" fontSize="10" fontWeight="700" fill={AMBER}>+4.2°</text>

      {/* Tracked skeleton */}
      <g stroke={INK} strokeOpacity="0.85" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" fill="none">
        {BONES.map(([a, b], i) => (
          <line key={i} x1={p(a)[0]} y1={p(a)[1]} x2={p(b)[0]} y2={p(b)[1]} />
        ))}
        <circle cx={p('head')[0]} cy={p('head')[1]} r="14" />
      </g>

      {/* Actual club shaft — the over-the-top delivery */}
      <line x1={p('hands')[0]} y1={p('hands')[1]} x2={p('clubhead')[0]} y2={p('clubhead')[1]} stroke={AMBER} strokeWidth="3" strokeLinecap="round" />

      {/* Joint markers */}
      {DOTS.map((k) => (
        <circle key={k} cx={p(k)[0]} cy={p(k)[1]} r="3.3" fill="#FCFBF8" stroke={INK} strokeWidth="1.5" />
      ))}
      {/* Contact point */}
      <circle cx={p('ball')[0]} cy={p('ball')[1]} r="5.5" fill="none" stroke={FAIRWAY} strokeWidth="2" />
      <circle cx={p('ball')[0]} cy={p('ball')[1]} r="1.8" fill={FAIRWAY} />

      {/* Fault callout — placed clear of the top toolbar */}
      <g transform="translate(232,168)">
        <rect x="0" y="0" width="150" height="34" rx="8" fill={AMBER} />
        <text x="13" y="15" fontFamily="Hubot Sans Variable, sans-serif" fontSize="10" fontWeight="700" letterSpacing="1.5" fill="#241600">OVER THE TOP</text>
        <text x="13" y="27" fontFamily="Hubot Sans Variable, sans-serif" fontSize="8.5" fontWeight="500" fill="#241600" fillOpacity="0.8">shaft steep at transition · P5</text>
      </g>
      <line x1="263" y1="86" x2="252" y2="168" stroke={AMBER} strokeWidth="1.1" strokeDasharray="2 2" />

      {/* On-plane confirmation lower in the swing */}
      <g transform="translate(24,250)">
        <rect x="0" y="0" width="98" height="20" rx="6" fill="#FCFBF8" stroke={INK} strokeOpacity="0.1" />
        <circle cx="12" cy="10" r="3" fill={FAIRWAY} />
        <text x="22" y="13.5" fontFamily="Hubot Sans Variable, sans-serif" fontSize="8.5" fontWeight="600" letterSpacing="1" fill={INK} fillOpacity="0.7">ON PLANE · P3</text>
      </g>

      {/* Video affordances */}
      <text x="16" y="346" fontFamily="Hubot Sans Variable, sans-serif" fontSize="8.5" fontWeight="600" letterSpacing="1.5" fill={INK} fillOpacity="0.4">YOUR CAPTURE · DTL</text>
      <text x="330" y="346" fontFamily="Hubot Sans Variable, sans-serif" fontSize="8.5" fontWeight="500" fill={INK} fillOpacity="0.4">00:03:12</text>

      <rect width="390" height="360" fill="url(#vig)" />
    </svg>
  )
}
