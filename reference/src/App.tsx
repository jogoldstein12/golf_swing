import { useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import SwingScene from './components/SwingScene'
import VideoAnalysis from './components/VideoAnalysis'
import { METRICS, SWING_SCORE, type Metric } from './data/swing'
import { CHECKPOINTS, SKELETONS, GOALS, type Checkpoint, type Marker } from './data/analysis'

type Pane = 'video' | '3d' | 'split'
const PANES: { id: Pane; label: string }[] = [
  { id: 'video', label: 'Video' },
  { id: '3d', label: '3D' },
  { id: 'split', label: 'Split' },
]

function Meter({ m }: { m: Metric }) {
  const inBand = m.fill >= m.band[0] && m.fill <= m.band[1]
  return (
    <div className="py-[18px]">
      <div className="flex items-baseline justify-between">
        <span className="label">{m.label}</span>
        <span className="font-display text-[26px] leading-none text-ink">
          {m.value}
          <span className="text-[15px] text-ink-45">{m.unit}</span>
        </span>
      </div>
      <div className="relative mt-[14px] h-[3px] w-full rounded-full bg-ink-08">
        <div
          className="absolute top-0 h-full rounded-full bg-fairway/45"
          style={{ left: `${m.band[0] * 100}%`, width: `${(m.band[1] - m.band[0]) * 100}%` }}
        />
        <div
          className="absolute -top-[3.5px] h-[10px] w-[10px] -translate-x-1/2 rounded-full border-[1.5px] border-bone"
          style={{ left: `${m.fill * 100}%`, background: inBand ? '#8FB80F' : '#191712' }}
        />
      </div>
    </div>
  )
}

function GoalCard({ g, i }: { g: (typeof GOALS)[number]; i: number }) {
  return (
    <div className="rounded-card bg-paper p-6 shadow-float">
      <div className="flex items-start gap-4">
        <span className="font-display mt-[2px] text-[30px] leading-none text-ink-25">{i + 1}</span>
        <div className="flex-1">
          <span className="label">{g.metric}</span>
          <h3 className="font-display mt-1 text-[22px] leading-tight text-ink">{g.title}</h3>
        </div>
      </div>
      <p className="mt-3 text-[13.5px] leading-relaxed text-ink-70">{g.detail}</p>
      <div className="mt-5 flex items-center gap-3">
        <span className="rounded-full bg-sand px-3 py-1 font-mono text-[11px] font-medium text-ink-70">
          {g.current}
        </span>
        <span className="text-ink-25">→</span>
        <span className="rounded-full bg-fairway/20 px-3 py-1 text-[11px] font-semibold text-[#5f7a08]">
          {g.target}
        </span>
      </div>
      <div className="mt-4 border-t border-ink-08 pt-3">
        <span className="label !text-ink-45">Drill</span>
        <p className="mt-1 text-[13px] leading-snug text-ink">{g.drill}</p>
      </div>
    </div>
  )
}

export default function App() {
  const [frame, setFrame] = useState<Checkpoint>('Top')
  const [pane, setPane] = useState<Pane>('video')
  const [marker, setMarker] = useState<Marker | null>(SKELETONS.Top.markers[0])

  const pickFrame = (c: Checkpoint) => {
    setFrame(c)
    setMarker(SKELETONS[c].markers[0] ?? null)
  }

  const videoOverlay = (
    <VideoAnalysis checkpoint={frame} onSelect={setMarker} selectedId={marker?.id} />
  )

  return (
    <div className="relative min-h-full w-full bg-bone grain">
      <div className="mx-auto flex min-h-full w-full max-w-[440px] flex-col px-6 pb-10 pt-[calc(env(safe-area-inset-top)+22px)]">
        {/* Top bar */}
        <header className="flex items-center justify-between">
          <span className="font-display text-[23px] leading-none tracking-tight text-ink">Swing Through</span>
          <div className="flex items-center gap-3">
            <span className="label !text-ink-70">Driver</span>
            <span className="h-[26px] w-[26px] rounded-full bg-ink" />
          </div>
        </header>

        {/* Section heading */}
        <div className="mt-9 flex items-end justify-between">
          <div>
            <span className="label">Swing Analysis</span>
            <h1 className="font-display mt-2 text-[34px] leading-[0.98] text-ink">
              Today, 7:42<span className="text-ink-25"> am</span>
            </h1>
          </div>
          <span className="label mb-1">03 · 07</span>
        </div>

        {/* Hero card */}
        <motion.div
          initial={{ opacity: 0, y: 14 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.7, ease: [0.22, 1, 0.36, 1] }}
          className="relative mt-5 overflow-hidden rounded-card bg-paper shadow-float"
        >
          <div className="absolute left-5 top-5 z-10 flex items-center gap-2">
            <span className="h-[6px] w-[6px] rounded-full bg-fairway-deep" />
            <span className="label">{SKELETONS[frame].label}</span>
          </div>
          {/* Pane toggle */}
          <div className="absolute right-4 top-4 z-10 flex rounded-full bg-bone/80 p-[3px] backdrop-blur">
            {PANES.map((pp) => (
              <button
                key={pp.id}
                onClick={() => setPane(pp.id)}
                className={`relative rounded-full px-[11px] py-[5px] text-[10px] font-semibold uppercase tracking-[0.12em] transition-colors ${
                  pane === pp.id ? 'text-bone' : 'text-ink-45'
                }`}
              >
                {pane === pp.id && (
                  <motion.span
                    layoutId="pane-pill"
                    className="absolute inset-0 rounded-full bg-ink"
                    transition={{ type: 'spring', stiffness: 400, damping: 34 }}
                  />
                )}
                <span className="relative">{pp.label}</span>
              </button>
            ))}
          </div>

          {/* Panes */}
          {pane === 'video' && <div className="h-[360px] w-full">{videoOverlay}</div>}
          {pane === '3d' && (
            <div className="h-[360px] w-full">
              <SwingScene />
            </div>
          )}
          {pane === 'split' && (
            <div className="w-full">
              <div className="h-[204px] w-full">{videoOverlay}</div>
              <div className="relative h-[176px] w-full border-t border-ink-08">
                <span className="label absolute left-5 top-3 z-10 !text-ink-25">3D · Drag to orbit</span>
                <SwingScene />
              </div>
            </div>
          )}

          {/* Checkpoint scrubber */}
          <div className="flex items-center justify-between border-t border-ink-08 px-2 py-1">
            {CHECKPOINTS.map((k) => (
              <button key={k} onClick={() => pickFrame(k)} className="relative flex-1 py-3 text-center">
                <span
                  className={`font-sans text-[12px] font-medium tracking-wide transition-colors ${
                    frame === k ? 'text-ink' : 'text-ink-25'
                  }`}
                >
                  {k}
                </span>
                {frame === k && (
                  <motion.span layoutId="kf" className="absolute inset-x-3 bottom-1 h-[2px] rounded-full bg-fairway-deep" />
                )}
              </button>
            ))}
          </div>
        </motion.div>

        {/* Marker detail sheet */}
        <AnimatePresence mode="wait">
          {marker && (
            <motion.div
              key={marker.id}
              initial={{ opacity: 0, y: -8, height: 0 }}
              animate={{ opacity: 1, y: 0, height: 'auto' }}
              exit={{ opacity: 0, y: -8, height: 0 }}
              transition={{ duration: 0.3, ease: [0.22, 1, 0.36, 1] }}
              className="overflow-hidden"
            >
              <div className="mt-4 flex items-start gap-3 rounded-card bg-paper p-5 shadow-float">
                <span
                  className="mt-[3px] flex h-[18px] w-[18px] shrink-0 items-center justify-center rounded-full text-[11px] font-bold text-paper"
                  style={{ background: marker.kind === 'good' ? '#7FA80C' : '#CE4A2C' }}
                >
                  {marker.kind === 'good' ? '✓' : '!'}
                </span>
                <div className="flex-1">
                  <div className="flex items-center justify-between">
                    <span className="label" style={{ color: marker.kind === 'good' ? '#5f7a08' : '#a53a22' }}>
                      {marker.kind === 'good' ? 'Working' : 'Needs work'}
                    </span>
                    <button onClick={() => setMarker(null)} className="text-ink-25">✕</button>
                  </div>
                  <h3 className="font-display mt-1 text-[20px] leading-tight text-ink">{marker.title}</h3>
                  <p className="mt-2 text-[13.5px] leading-relaxed text-ink-70">{marker.detail}</p>
                </div>
              </div>
            </motion.div>
          )}
        </AnimatePresence>

        {/* Score + verdict */}
        <div className="mt-10 flex items-start justify-between">
          <div>
            <span className="label">Swing Score</span>
            <div className="mt-1 flex items-baseline gap-1">
              <span className="font-display text-[72px] leading-[0.8] text-ink">{SWING_SCORE}</span>
              <span className="font-display text-[24px] text-ink-25">/100</span>
            </div>
          </div>
          <p className="font-display mt-1 max-w-[46%] text-right text-[19px] italic leading-snug text-ink-70">
            Compact and powerful — the shaft steepens slightly at the top.
          </p>
        </div>

        <div className="mt-8 h-px w-full bg-ink-08" />

        {/* Metrics */}
        <div className="mt-2 divide-y divide-ink-08">
          {METRICS.map((m) => (
            <Meter key={m.label} m={m} />
          ))}
        </div>

        {/* Goals */}
        <div className="mt-10">
          <div className="flex items-baseline justify-between">
            <span className="label">Your Goals</span>
            <span className="label !text-ink-25">Priority order</span>
          </div>
          <div className="mt-4 space-y-4">
            {GOALS.map((g, i) => (
              <GoalCard key={g.title} g={g} i={i} />
            ))}
          </div>
        </div>

        {/* Primary action */}
        <button className="mt-9 flex w-full items-center justify-center rounded-full bg-ink py-[18px] text-[15px] font-medium tracking-wide text-bone transition-transform active:scale-[0.99]">
          Record next swing
        </button>
      </div>
    </div>
  )
}
