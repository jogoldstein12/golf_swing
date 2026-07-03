// Swing-plane + skeletal-tracking overlay for the down-the-line video view. Renders the
// tracked skeleton for the active checkpoint with interactive good/fault markers (tap to
// expand). On a capture stand-in here; feed pose-estimation joint tracks in to go live.
import { BONES2D, PLANE_LINE, SKELETONS, type Checkpoint, type Marker } from '../data/analysis'

const INK = '#191712'
const FAIRWAY = '#7FA80C'
const AMBER = '#DB851F'
const RED = '#CE4A2C'

export default function VideoAnalysis({
  checkpoint,
  onSelect,
  selectedId,
}: {
  checkpoint: Checkpoint
  onSelect: (m: Marker) => void
  selectedId?: string
}) {
  const s = SKELETONS[checkpoint]
  const p = (k: string) => s.joints[k]
  const over = s.planeState === 'over'
  const [handsKey, clubhead] = s.club
  const hands = p(handsKey)

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

      <rect width="390" height="360" fill="url(#cap)" />

      {/* Base swing plane reference */}
      <line
        x1={PLANE_LINE.x1} y1={PLANE_LINE.y1} x2={PLANE_LINE.x2} y2={PLANE_LINE.y2}
        stroke={FAIRWAY} strokeWidth="1.8" strokeDasharray="1 6" strokeLinecap="round"
        opacity={s.planeState === 'none' ? 0.35 : 1}
      />

      {/* Plane-gap indicator when over the top */}
      {over && (
        <>
          <line x1={clubhead[0]} y1={clubhead[1]} x2={clubhead[0]} y2="156" stroke={AMBER} strokeWidth="1.4" strokeDasharray="3 3" />
          <text x={clubhead[0] + 6} y="120" fontFamily="Hubot Sans Variable, sans-serif" fontSize="10" fontWeight="700" fill={AMBER}>+4.2°</text>
        </>
      )}

      {/* Tracked skeleton */}
      <g stroke={INK} strokeOpacity="0.85" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" fill="none">
        {BONES2D.map(([a, b], i) =>
          s.joints[a] && s.joints[b] ? (
            <line key={i} x1={p(a)[0]} y1={p(a)[1]} x2={p(b)[0]} y2={p(b)[1]} />
          ) : null,
        )}
        <circle cx={p('head')[0]} cy={p('head')[1]} r="14" />
      </g>

      {/* Club shaft — amber when off-plane, ink otherwise */}
      <line
        x1={hands[0]} y1={hands[1]} x2={clubhead[0]} y2={clubhead[1]}
        stroke={over ? AMBER : INK} strokeOpacity={over ? 1 : 0.85} strokeWidth={over ? 3 : 2.4} strokeLinecap="round"
      />

      {/* Contact point at address/impact */}
      {(checkpoint === 'Address' || checkpoint === 'Impact') && (
        <>
          <circle cx={clubhead[0]} cy={clubhead[1]} r="5.5" fill="none" stroke={FAIRWAY} strokeWidth="2" />
          <circle cx={clubhead[0]} cy={clubhead[1]} r="1.8" fill={FAIRWAY} />
        </>
      )}

      {/* Interactive good / fault markers */}
      {s.markers.map((m) => {
        const c = p(m.at)
        const col = m.kind === 'good' ? FAIRWAY : RED
        const sel = selectedId === m.id
        return (
          <g key={m.id} onClick={() => onSelect(m)} style={{ cursor: 'pointer' }}>
            {sel && <circle cx={c[0]} cy={c[1]} r="15" fill={col} fillOpacity="0.14" />}
            <circle cx={c[0]} cy={c[1]} r="9" fill="#FCFBF8" stroke={col} strokeWidth="2.2" />
            {m.kind === 'good' ? (
              <path d={`M ${c[0] - 3.4} ${c[1]} l 2.4 2.6 l 4.6 -5.2`} fill="none" stroke={col} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
            ) : (
              <g stroke={col} strokeWidth="2" strokeLinecap="round">
                <line x1={c[0] - 2.8} y1={c[1] - 2.8} x2={c[0] + 2.8} y2={c[1] + 2.8} />
                <line x1={c[0] + 2.8} y1={c[1] - 2.8} x2={c[0] - 2.8} y2={c[1] + 2.8} />
              </g>
            )}
          </g>
        )
      })}

      {/* Affordances */}
      <text x="16" y="346" fontFamily="Hubot Sans Variable, sans-serif" fontSize="8.5" fontWeight="600" letterSpacing="1.5" fill={INK} fillOpacity="0.4">YOUR CAPTURE · DTL</text>
      <text x="330" y="346" fontFamily="Hubot Sans Variable, sans-serif" fontSize="8.5" fontWeight="500" fill={INK} fillOpacity="0.4">00:03:12</text>

      <rect width="390" height="360" fill="url(#vig)" pointerEvents="none" />
    </svg>
  )
}
