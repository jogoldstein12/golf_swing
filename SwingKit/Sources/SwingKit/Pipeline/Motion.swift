// Shared "how fast is the grip moving, and where is it still" primitives used by both
// the coarse whole-clip window finder and the fine-grained P1-P10 checkpoint detector.
import Foundation
import simd

enum Motion {
    struct QuietRun { var startIndex: Int; var endIndex: Int } // inclusive, in `times`/`speed` index space

    /// Per-frame grip position (2D, smoothed-track expected) and scalar speed
    /// (normalized image units / second) from the SG derivative of x and y.
    static func gripSpeed2D(_ frames: [PoseFrame]) -> (times: [Double], grip: [SIMD2<Double>], speed: [Double])? {
        let times = frames.map(\.time)
        var xs = [Double](repeating: .nan, count: frames.count)
        var ys = [Double](repeating: .nan, count: frames.count)
        for (i, f) in frames.enumerated() {
            if let g = f.grip2 { xs[i] = g.x; ys[i] = g.y }
        }
        guard let fx = Filters.fillGaps(xs), let fy = Filters.fillGaps(ys) else { return nil }
        let vx = Smoothing.velocity(fx, times: times)
        let vy = Smoothing.velocity(fy, times: times)
        let speed = zip(vx, vy).map { sqrt($0 * $0 + $1 * $1) }
        let grip = zip(fx, fy).map { SIMD2($0, $1) }
        return (times, grip, speed)
    }

    /// Runs where `speed` stays below `threshold`, small gaps (<= mergeGap seconds)
    /// bridged so one noisy sample doesn't fragment a real stillness period, and only
    /// runs lasting >= minDuration seconds kept.
    static func quietRuns(times: [Double], speed: [Double], threshold: Double,
                          minDuration: Double, mergeGap: Double = 0.12) -> [QuietRun] {
        guard !speed.isEmpty else { return [] }
        var still = speed.map { $0 < threshold }
        // bridge short gaps
        var i = 0
        while i < still.count {
            if !still[i] {
                var j = i
                while j < still.count && !still[j] { j += 1 }
                let gapDuration = times[min(j, times.count - 1)] - times[i]
                if i > 0, j < still.count, gapDuration <= mergeGap {
                    for k in i..<j { still[k] = true }
                }
                i = j
            } else { i += 1 }
        }
        var runs: [QuietRun] = []
        i = 0
        while i < still.count {
            guard still[i] else { i += 1; continue }
            var j = i
            while j < still.count && still[j] { j += 1 }
            let duration = times[j - 1] - times[i]
            if duration >= minDuration { runs.append(QuietRun(startIndex: i, endIndex: j - 1)) }
            i = j
        }
        return runs
    }
}
