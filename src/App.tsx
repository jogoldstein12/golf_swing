import { useState } from 'react'
import { motion } from 'framer-motion'
import SwingScene from './components/SwingScene'
import VideoAnalysis from './components/VideoAnalysis'
import { METRICS, SWING_SCORE, type Metric } from './data/swing'

const KEYFRAMES = ['Address', 'Top', 'Impact', 'Follow'] as const

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
        {/* ideal band */}
        <div
          className="absolute top-0 h-full rounded-full bg-fairway/45"
          style={{ left: `${m.band[0] * 100}%`, width: `${(m.band[1] - m.band[0]) * 100}%` }}
        />
        {/* marker */}
        <div
          className="absolute -top-[3.5px] h-[10px] w-[10px] -translate-x-1/2 rounded-full border-[1.5px] border-bone"
          style={{ left: `${m.fill * 100}%`, background: inBand ? '#8FB80F' : '#191712' }}
        />
      </div>
    </div>
  )
}

export default function App() {
  const [frame, setFrame] = useState<(typeof KEYFRAMES)[number]>('Top')
  const [pane, setPane] = useState<'video' | '3d'>('video')

  return (
    <div className="relative min-h-full w-full bg-bone grain">
      <div className="mx-auto flex min-h-full w-full max-w-[440px] flex-col px-6 pb-10 pt-[calc(env(safe-area-inset-top)+22px)]">
        {/* Top bar */}
        <header className="flex items-center justify-between">
          <span className="font-display text-[23px] leading-none tracking-tight text-ink">
            Swing Through
          </span>
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

        {/* Hero: 3D swing */}
        <motion.div
          initial={{ opacity: 0, y: 14 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.7, ease: [0.22, 1, 0.36, 1] }}
          className="relative mt-5 overflow-hidden rounded-card bg-paper shadow-float"
        >
          <div className="absolute left-5 top-5 z-10 flex items-center gap-2">
            <span className="h-[6px] w-[6px] rounded-full bg-fairway-deep" />
            <span className="label">
              {frame} · {pane === 'video' ? 'Down the line' : '3D'}
            </span>
          </div>
          {/* Video / 3D toggle */}
          <div className="absolute right-4 top-4 z-10 flex rounded-full bg-bone/80 p-[3px] backdrop-blur">
            {(['video', '3d'] as const).map((p) => (
              <button
                key={p}
                onClick={() => setPane(p)}
                className={`relative rounded-full px-3 py-[5px] text-[10px] font-semibold uppercase tracking-[0.14em] transition-colors ${
                  pane === p ? 'text-bone' : 'text-ink-45'
                }`}
              >
                {pane === p && (
                  <motion.span
                    layoutId="pane-pill"
                    className="absolute inset-0 rounded-full bg-ink"
                    transition={{ type: 'spring', stiffness: 400, damping: 34 }}
                  />
                )}
                <span className="relative">{p === 'video' ? 'Video' : '3D'}</span>
              </button>
            ))}
          </div>
          <div className="relative h-[360px] w-full">
            {pane === 'video' ? <VideoAnalysis /> : <SwingScene />}
          </div>
          {/* Keyframe scrubber */}
          <div className="flex items-center justify-between border-t border-ink-08 px-2 py-1">
            {KEYFRAMES.map((k) => (
              <button
                key={k}
                onClick={() => setFrame(k)}
                className="relative flex-1 py-3 text-center"
              >
                <span
                  className={`font-sans text-[12px] font-medium tracking-wide transition-colors ${
                    frame === k ? 'text-ink' : 'text-ink-25'
                  }`}
                >
                  {k}
                </span>
                {frame === k && (
                  <motion.span
                    layoutId="kf"
                    className="absolute inset-x-3 bottom-1 h-[2px] rounded-full bg-fairway-deep"
                  />
                )}
              </button>
            ))}
          </div>
        </motion.div>

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

        {/* Coaching note */}
        <div className="mt-8 rounded-card bg-sand/70 p-6">
          <span className="label">Primary Focus · Downswing</span>
          <p className="font-display mt-3 text-[22px] italic leading-snug text-ink">
            “Feel the trail elbow lead into the downswing to shallow the shaft — this drops the club
            onto plane and squares the face sooner.”
          </p>
          <button className="mt-5 inline-flex items-center gap-2">
            <span className="label !text-ink">View the drill</span>
            <span className="text-ink">→</span>
          </button>
        </div>

        {/* Primary action */}
        <button className="mt-9 flex w-full items-center justify-center rounded-full bg-ink py-[18px] text-[15px] font-medium tracking-wide text-bone transition-transform active:scale-[0.99]">
          Record next swing
        </button>
      </div>
    </div>
  )
}
