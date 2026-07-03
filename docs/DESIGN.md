# Swing Through — Design System

A professional golf-swing analysis app. Aesthetic intent: an **editorial golf lab** —
bright, airy, sculptural, human-designed. Explicitly NOT generic AI-app slop (no emoji
icons, no default gradients, no stock fonts, no visual glitches).

## Color
- Canvas: warm bone `#F5F3EE` (never pure white). Cards on `#FCFBF8`, surfaces `#EBE7DE`.
- Ink: warm near-black `#191712` (never `#000`), with 70/45/25/08% opacity steps.
- Signature accent: `#B4E019` "fairway" (deep `#8FB80F`). Used on <5% of surface —
  live/active measurement + the primary action only. Never decorative.

## Type (deliberately non-generic — avoids the Inter/Geist default tell)
- Display: **Instrument Serif** — wordmark, hero numerals, editorial pull-quotes.
- UI + technical readouts: **Hubot Sans** (variable).
- Intended UI face for the native build: **Satoshi** (Fontshare — blocked by this
  sandbox's proxy, so Hubot Sans stands in here; swap to Satoshi on the Mac build).

## The 3D hero
The swing rendered as a sculptural **clay artist's-mannequin** (capsule limbs, warm
matte clay `#AA9A7E`), orbitable, on soft contact shadows. Overlays: a translucent
**swing plane** disc and the **clubhead path** arc (fairway) from impact to top of
backswing, marker at the top. Keyframe scrubber: Address · Top · Impact · Follow.
Reference feel: MetalSplatter depth, Airbnb warmth, editorial magazine layout.

## Motion
Spring-based, physical, frame-perfect. Verified against dumped frames (Playwright +
ffmpeg) — no pops or hitches. Shared-element transitions between views.

## Stack (prototype)
Vite + React + TypeScript, react-three-fiber / three.js, Tailwind, Framer Motion.
Self-verify loop: `tools/shot.mjs` screenshots the running app for pixel review.
