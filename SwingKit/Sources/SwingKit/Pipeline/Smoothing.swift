// Measurement layer, stage 2: confidence-gated smoothing of the raw joint tracks.
//
// Real footage has two failure modes we must not let leak into biomechanics:
//  1. Single-frame mis-tracks (an arm briefly jumps to the wrong place in fast motion,
//     e.g. transition motion blur) — Hampel kills these without touching real motion.
//  2. Sustained low-confidence stretches (a joint occluded or blurred for several
//     frames — we saw this on the real samples: the lead wrist's 2D confidence drops
//     to ~0.1-0.3 for a run of frames through the downswing while the trail wrist
//     stays ~0.6-0.8). Below `confidenceThreshold` we discard the raw sample entirely
//     and linearly interpolate across the gap rather than trust a low-confidence
//     detection — better an honest interpolation than a noisy "real" sample.
// Both stages build on Filters.swift (already validated: zero-phase, doesn't lag
// peaks). Output is a same-shaped [PoseFrame] with cleaned j2/j3; `confidence` is left
// untouched (it still records what Vision actually saw, for any UI that wants it).
import Foundation
import simd

enum Smoothing {
    struct Options: Sendable {
        /// Below this, a joint sample is treated as missing (gap-filled, not trusted).
        var confidenceThreshold: Double
        var hampelHalfWindow: Int
        var hampelK: Double
        var sgHalfWindow: Int
        init(confidenceThreshold: Double = 0.15, hampelHalfWindow: Int = 2,
             hampelK: Double = 3.0, sgHalfWindow: Int = 2) {
            self.confidenceThreshold = confidenceThreshold
            self.hampelHalfWindow = hampelHalfWindow
            self.hampelK = hampelK
            self.sgHalfWindow = sgHalfWindow
        }
    }

    /// Confidence-gate, gap-fill, de-spike, and smooth every joint's 2D and 3D track
    /// independently (each axis is its own scalar series through Filters). A joint
    /// that never clears the confidence threshold anywhere in the clip is left absent
    /// (nil) in every output frame — never fabricated from nothing.
    static func smooth(_ frames: [PoseFrame], options: Options = .init()) -> [PoseFrame] {
        guard frames.count > 1 else { return frames }
        var out = frames
        let n = frames.count

        func gate(_ raw: [Double?]) -> [Double]? {
            let series = raw.map { $0 ?? .nan }
            guard let filled = Filters.fillGaps(series) else { return nil }
            let despiked = Filters.hampel(filled, halfWindow: options.hampelHalfWindow, k: options.hampelK)
            return Filters.savitzkyGolay(despiked, halfWindow: options.sgHalfWindow)
        }

        for joint in Joint.allCases {
            // 2D
            var rawX = [Double?](repeating: nil, count: n)
            var rawY = [Double?](repeating: nil, count: n)
            for i in 0..<n {
                guard let p = frames[i].j2[joint],
                      (frames[i].confidence[joint] ?? 1) >= options.confidenceThreshold else { continue }
                rawX[i] = p.x; rawY[i] = p.y
            }
            if let sx = gate(rawX), let sy = gate(rawY) {
                for i in 0..<n { out[i].j2[joint] = SIMD2(sx[i], sy[i]) }
            } else {
                for i in 0..<n { out[i].j2[joint] = nil }
            }

            // 3D (same confidence gate — Vision only publishes one per-joint
            // confidence map, from the 2D request; we reuse it for 3D reliability
            // since a joint Vision can't see well in 2D isn't well-reconstructed in
            // 3D either).
            var rawX3 = [Double?](repeating: nil, count: n)
            var rawY3 = [Double?](repeating: nil, count: n)
            var rawZ3 = [Double?](repeating: nil, count: n)
            for i in 0..<n {
                guard let p = frames[i].j3[joint],
                      (frames[i].confidence[joint] ?? 1) >= options.confidenceThreshold else { continue }
                rawX3[i] = p.x; rawY3[i] = p.y; rawZ3[i] = p.z
            }
            if let sx = gate(rawX3), let sy = gate(rawY3), let sz = gate(rawZ3) {
                for i in 0..<n { out[i].j3[joint] = SIMD3(sx[i], sy[i], sz[i]) }
            } else {
                for i in 0..<n { out[i].j3[joint] = nil }
            }
        }
        return out
    }

    /// Median sampling interval — used to scale SG derivative kernels (per-sample) to
    /// per-second. Robust to the odd dropped/duplicated frame.
    static func medianDT(_ times: [Double]) -> Double {
        guard times.count > 1 else { return 1.0 / 25.0 }
        var diffs = zip(times.dropFirst(), times).map { $0 - $1 }
        diffs.sort()
        return diffs[diffs.count / 2]
    }

    /// Velocity of a scalar series (units of x per second), via the SG derivative
    /// kernel — an analytic derivative of the local quadratic fit, not raw differencing.
    static func velocity(_ x: [Double], times: [Double], halfWindow: Int = 2) -> [Double] {
        let dt = medianDT(times)
        guard dt > 0 else { return [Double](repeating: 0, count: x.count) }
        return Filters.savitzkyGolayDerivative(x, halfWindow: halfWindow).map { $0 / dt }
    }
}
