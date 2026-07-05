// A1 — Deterministic plausibility gating. Coverage and orientation confidence tell us
// how much of the golfer we saw and how steady the orientation stream was; they do NOT
// tell us whether a produced NUMBER is physically possible. A degenerate 3D yaw can
// yield "4° shoulder turn" with high coverage and a confident-looking score — the exact
// failure documented in docs/BETA_FEATURES_SPEC.md (A0): a 4.2° shoulder turn / 2.6°
// X-factor report that still reported orientationConfidence ≈ 0.84 and availability
// `.available`.
//
// This gate is the floor beneath everything else: a pure function over the already-built
// metrics + ReportQuality that WITHHOLDS anatomically impossible values (it never clamps
// them — a clamped value is a fabricated measurement) and feeds a plausibility signal
// back into orientation confidence so the existing score gate responds. No ML, no
// thresholds hidden in the UI.
import Foundation

public enum PlausibilityGate {
    /// Anatomical validity envelopes — "possible for a human," deliberately WIDER than
    /// the ideal bands in docs/SWING_MODEL.md. A value outside its envelope is not a bad
    /// swing, it is a broken measurement. Keyed by `MetricValue.label`. Signed metrics
    /// (plane deviation) use a symmetric range, so the check is an implicit |Δ| bound.
    static let envelopes: [String: ClosedRange<Double>] = [
        "Shoulder Turn": 20...150,
        "Hip Turn": 5...90,
        "X-Factor at Transition": 5...80,
        "Spine Angle": 15...55,
        "Swing Plane": -25...25,
        "Tempo": 1.0...6.0,
    ]

    /// Metrics derived from the 3D body-orientation (yaw) stream. When one of these is
    /// implausible the orientation estimate itself is suspect — not just the one number —
    /// so we lower `orientationConfidence`. That is A1's "missing link": the score gate
    /// keys off orientation confidence, so this is what would have caught A0.
    static let orientationRotationFamily: Set<String> =
        ["Shoulder Turn", "Hip Turn", "X-Factor at Transition"]

    /// Orientation confidence to fall back to when the rotation family is implausible —
    /// low enough that `MetricsBuilder.score`'s orientation gate flips the report to
    /// `.insufficientData` (see that gate's threshold).
    static let implausibleOrientationConfidence = 0.15

    public struct Result: Sendable {
        public var metrics: [MetricValue]
        public var quality: ReportQuality
        public init(metrics: [MetricValue], quality: ReportQuality) {
            self.metrics = metrics
            self.quality = quality
        }
    }

    /// Pure function: withhold implausible metrics and, when a 3D-rotation metric is
    /// implausible, degrade orientation confidence so the score gate responds. Order in,
    /// order out; metric values are preserved verbatim for diagnostics.
    public static func apply(metrics: [MetricValue], quality: ReportQuality) -> Result {
        var out: [MetricValue] = []
        out.reserveCapacity(metrics.count)
        var rotationImplausible = false

        for var metric in metrics {
            guard let envelope = envelopes[metric.label], !envelope.contains(metric.value) else {
                out.append(metric)
                continue
            }
            let base = metric.quality
                ?? MeasurementQuality(confidence: 0, coverage: 0, provenance: .measured)
            metric.quality = MeasurementQuality(
                confidence: min(base.confidence, 0.1),
                coverage: base.coverage,
                provenance: .unavailable,
                warnings: base.warnings + [warning(for: metric, envelope: envelope)]
            )
            out.append(metric)
            if orientationRotationFamily.contains(metric.label) { rotationImplausible = true }
        }

        guard rotationImplausible else { return Result(metrics: out, quality: quality) }

        let adjusted = ReportQuality(
            twoDCoverage: quality.twoDCoverage,
            threeDCoverage: quality.threeDCoverage,
            checkpointConfidence: quality.checkpointConfidence,
            orientationConfidence: min(quality.orientationConfidence, implausibleOrientationConfidence),
            planeBasis: quality.planeBasis,
            warnings: quality.warnings + [
                "3D body rotation produced anatomically impossible values; the orientation estimate was treated as untrusted."
            ]
        )
        return Result(metrics: out, quality: adjusted)
    }

    private static func warning(for metric: MetricValue, envelope: ClosedRange<Double>) -> String {
        String(
            format: "%@ measured %.1f%@, outside the anatomically possible range (%.0f–%.0f%@); it was withheld as an unreliable measurement.",
            metric.label, metric.value, metric.unit,
            envelope.lowerBound, envelope.upperBound, metric.unit
        )
    }
}
