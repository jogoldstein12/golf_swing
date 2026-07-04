// Numerical filters used across the measurement pipeline.
//
// Design (all offline — we never filter causally, so zero-phase filters are used):
//  * Hampel: kills single-frame outliers (the occasional wrist/arm mis-track in
//    transition) by comparing each sample to the local median; replaced only when
//    it is a > k·MAD outlier, so genuine fast motion survives.
//  * Savitzky-Golay (order 2): local quadratic least-squares fit. Centered window →
//    zero lag; order-2 fit preserves quadratic peaks exactly, which matters at 25 fps
//    where a downswing is ~6 frames and a lagging filter would visibly shift impact.
//  * Derivatives come from the SG derivative kernel (analytic derivative of the local
//    fit) — far better behaved than differencing raw samples.
import Foundation

enum Filters {

    /// Hampel outlier rejection. `halfWindow` frames each side, threshold `k` robust
    /// standard deviations (1.4826·MAD). Returns a copy with outliers replaced by the
    /// local median.
    static func hampel(_ x: [Double], halfWindow: Int = 2, k: Double = 3.0) -> [Double] {
        guard x.count > 2 * halfWindow else { return x }
        var out = x
        for i in x.indices {
            let lo = max(0, i - halfWindow), hi = min(x.count - 1, i + halfWindow)
            var w = Array(x[lo...hi])
            w.sort()
            let med = w[w.count / 2]
            var dev = w.map { abs($0 - med) }
            dev.sort()
            let mad = dev[dev.count / 2]
            let sigma = 1.4826 * mad + 1e-12
            if abs(x[i] - med) > k * sigma { out[i] = med }
        }
        return out
    }

    /// Savitzky-Golay smoothing, polynomial order 2, centered window of `2m+1`.
    /// Edges are handled by reflecting the series (standard practice; avoids the
    /// shrink-to-zero bias of zero padding).
    static func savitzkyGolay(_ x: [Double], halfWindow m: Int = 2) -> [Double] {
        convolveReflected(x, kernel: sgSmoothKernel(m: m))
    }

    /// Savitzky-Golay first derivative (units of x per sample). Divide by dt for
    /// units per second.
    static func savitzkyGolayDerivative(_ x: [Double], halfWindow m: Int = 2) -> [Double] {
        convolveReflected(x, kernel: sgDerivKernel(m: m))
    }

    /// Order-2 SG smoothing kernel for window [-m, m]. Closed form: the least-squares
    /// quadratic fit evaluated at 0 is a linear combination of samples with weights
    /// w_i = (3(3m² + 3m − 1) − 15 i²) / ((2m+3)(2m+1)(2m−1)).
    static func sgSmoothKernel(m: Int) -> [Double] {
        precondition(m >= 1)
        let denom = Double((2 * m + 3) * (2 * m + 1) * (2 * m - 1))
        return (-m...m).map { i in
            (3.0 * Double(3 * m * m + 3 * m - 1) - 15.0 * Double(i * i)) / denom
        }
    }

    /// Order-2 SG derivative kernel: the fitted quadratic's slope at 0 reduces to the
    /// classic w_i = i / Σi² (same as for a linear fit — the quadratic term is even).
    static func sgDerivKernel(m: Int) -> [Double] {
        precondition(m >= 1)
        let sumSq = Double((-m...m).reduce(0) { $0 + $1 * $1 })
        return (-m...m).map { Double($0) / sumSq }
    }

    /// Convolve with a centered kernel, reflecting the series at both ends.
    static func convolveReflected(_ x: [Double], kernel: [Double]) -> [Double] {
        let m = kernel.count / 2
        guard x.count > 1 else { return x }
        let n = x.count
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n {
            var acc = 0.0
            for (j, w) in kernel.enumerated() {
                var idx = i + j - m
                if idx < 0 { idx = -idx }                       // reflect left
                if idx >= n { idx = 2 * (n - 1) - idx }         // reflect right
                acc += w * x[max(0, min(n - 1, idx))]
            }
            out[i] = acc
        }
        return out
    }

    /// Linear interpolation over gaps (NaN samples). Leading/trailing gaps are filled
    /// with the nearest valid value. Returns nil if there are no valid samples.
    static func fillGaps(_ x: [Double]) -> [Double]? {
        guard x.contains(where: { !$0.isNaN }) else { return nil }
        var out = x
        // forward pass: remember last valid, fill runs on encountering next valid
        var lastValid = -1
        for i in out.indices {
            if !out[i].isNaN {
                if lastValid < i - 1 {
                    if lastValid == -1 {
                        for j in 0..<i { out[j] = out[i] }
                    } else {
                        let a = out[lastValid], b = out[i]
                        let span = Double(i - lastValid)
                        for j in (lastValid + 1)..<i {
                            out[j] = a + (b - a) * Double(j - lastValid) / span
                        }
                    }
                }
                lastValid = i
            }
        }
        if lastValid < out.count - 1, lastValid >= 0 {
            for j in (lastValid + 1)..<out.count { out[j] = out[lastValid] }
        }
        return out
    }

    /// Sub-frame zero crossing: linear interp between samples i and i+1 of `y`
    /// (times `t`). Returns nil if no sign change in [i, i+1].
    static func zeroCrossing(t: [Double], y: [Double], after i: Int) -> Double? {
        guard i >= 0, i + 1 < y.count else { return nil }
        let a = y[i], b = y[i + 1]
        guard a == 0 || b == 0 || (a < 0) != (b < 0) else { return nil }
        if a == b { return t[i] }
        let f = a / (a - b)
        return t[i] + f * (t[i + 1] - t[i])
    }

    /// Sub-frame extremum: parabola through (i-1, i, i+1) around a discrete peak.
    /// Returns (time, value). Falls back to the sample itself at the edges.
    static func parabolicPeak(t: [Double], y: [Double], at i: Int) -> (time: Double, value: Double) {
        guard i > 0, i + 1 < y.count else { return (t[i], y[i]) }
        let y0 = y[i - 1], y1 = y[i], y2 = y[i + 1]
        let denom = y0 - 2 * y1 + y2
        guard abs(denom) > 1e-12 else { return (t[i], y[i]) }
        let delta = 0.5 * (y0 - y2) / denom          // in samples, ∈ (-1, 1) at a true peak
        let clamped = max(-1, min(1, delta))
        let dt = i + 1 < t.count ? (t[i + 1] - t[i]) : (t[i] - t[i - 1])
        let value = y1 - 0.25 * (y0 - y2) * clamped
        return (t[i] + clamped * dt, value)
    }

    /// Wrap-aware unwrap for angle series in degrees (removes ±360 jumps).
    static func unwrapDegrees(_ x: [Double]) -> [Double] {
        guard x.count > 1 else { return x }
        var out = x
        var offset = 0.0
        for i in 1..<x.count {
            var d = x[i] - x[i - 1]
            while d > 180 { d -= 360; offset -= 360 }
            while d < -180 { d += 360; offset += 360 }
            out[i] = x[i] + offset
        }
        return out
    }
}
