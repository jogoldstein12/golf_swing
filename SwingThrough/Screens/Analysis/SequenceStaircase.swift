// NP-3 — the kinematic-sequence "power staircase": four color-coded angular-velocity
// traces (pelvis, torso, lead arm, club) with peak markers, showing whether the
// downswing unloaded in the ideal ground-up order. This is depth, not the novice's one
// cue, so it lives collapsed below MetricsSection.
//
// Honest by construction: a low-confidence read, an incomplete peak set, or a degenerate
// one (pelvis and torso peaking within a sub-frame of each other — see
// `KinematicSequence.isDegenerate`) can't be trusted to judge order, so the panel greys
// out and says so in plain language instead of asserting a staircase that isn't there.
// `series`/`times` being empty (peaks-only fixtures, e.g. DemoData) draws just the peak
// markers + the verdict/caption — never a fabricated curve.
import SwiftUI
import SwingKit

enum SequencePresentation {
    /// True only when the peak read is complete (all four segments), confident
    /// (`lowConfidence` not true), and resolvable (pelvis/torso didn't peak together).
    /// Anything else and an order claim would be noise dressed as signal.
    static func isTrustworthy(_ seq: KinematicSequence) -> Bool {
        seq.peaks.count == 4 && seq.lowConfidence != true && !seq.isDegenerate
    }
}

/// Collapsible "Power sequence" panel, placed below MetricsSection. Mirrors
/// MetricsSection's own progressive-disclosure shape (Hairline + DisclosureGroup).
struct PowerSequenceSection: View {
    let sequence: KinematicSequence
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            DisclosureGroup(isExpanded: $expanded) {
                SequenceStaircase(sequence: sequence)
                    .padding(.top, 18)
                    .padding(.bottom, 6)
            } label: {
                MicroLabel(expanded ? "Hide power sequence" : "Power sequence", color: .ink45)
                    .padding(.vertical, 16)
                    .contentShape(Rectangle())
            }
            .tint(.ink45)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("powerSequenceSection")
    }
}

/// The chart + verdict/caption. Exposed standalone so it can be previewed/tested apart
/// from the disclosure chrome around it.
struct SequenceStaircase: View {
    let sequence: KinematicSequence

    private var trustworthy: Bool { SequencePresentation.isTrustworthy(sequence) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            legend
            chart
                .frame(height: 132)
            verdict
        }
    }

    // MARK: legend

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(KinematicSequence.Segment.allCases, id: \.self) { segment in
                HStack(spacing: 5) {
                    Circle().fill(markColor(segment)).frame(width: 7, height: 7)
                    Text(segment.stairLabel)
                        .font(Type.ui(10, .medium))
                        .foregroundStyle(Color.ink45)
                }
            }
        }
    }

    // MARK: chart

    private var chart: some View {
        Canvas { ctx, size in
            let plot = CGRect(x: 6, y: 24, width: max(0, size.width - 12), height: max(0, size.height - 32))
            drawBaseline(&ctx, plot: plot)
            drawTraces(&ctx, plot: plot)
            drawPeaks(&ctx, plot: plot)
        }
    }

    private func drawBaseline(_ ctx: inout GraphicsContext, plot: CGRect) {
        var baseline = Path()
        baseline.move(to: CGPoint(x: plot.minX, y: plot.maxY))
        baseline.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
        ctx.stroke(baseline, with: .color(.ink08), style: .init(lineWidth: 1))
    }

    /// Draws a trace only when the pipeline actually measured one at every sampled
    /// time — `series`/`times` are empty for peaks-only fixtures, and a partial or
    /// mismatched-length series is skipped rather than interpolated into a fake line.
    private func drawTraces(_ ctx: inout GraphicsContext, plot: CGRect) {
        guard !sequence.times.isEmpty else { return }
        for segment in KinematicSequence.Segment.allCases {
            guard let values = sequence.series[segment],
                  values.count == sequence.times.count, values.count > 1 else { continue }
            var path = Path()
            for (i, t) in sequence.times.enumerated() {
                let p = point(time: t, value: values[i], in: plot)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            ctx.stroke(path, with: .color(markColor(segment)),
                       style: .init(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }

    private func drawPeaks(_ ctx: inout GraphicsContext, plot: CGRect) {
        for (i, peak) in sequence.peaks.enumerated() {
            let p = point(time: peak.time, value: peak.peakDegPerSec, in: plot)
            let color = markColor(peak.segment)
            let dot = CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)
            ctx.fill(Path(ellipseIn: dot), with: .color(color))
            ctx.stroke(Path(ellipseIn: dot), with: .color(.paper), style: .init(lineWidth: 1.2))

            let labelX = min(max(p.x, plot.minX + 28), plot.maxX - 28)
            let labelY = max(p.y - 12 - CGFloat(i % 2) * 12, plot.minY - 12)
            let text = Text("\(peak.segment.stairLabel) · \(String(format: "%.2fs", peak.time))")
                .font(Type.ui(9, .medium))
                .foregroundStyle(color)
            ctx.draw(text, at: CGPoint(x: labelX, y: labelY), anchor: .center)
        }
    }

    // MARK: scaling

    private var allTimes: [Double] { sequence.times + sequence.peaks.map(\.time) }
    private var allValues: [Double] {
        sequence.series.values.flatMap { $0 } + sequence.peaks.map(\.peakDegPerSec)
    }
    private var timeRange: ClosedRange<Double> {
        guard let lo = allTimes.min(), let hi = allTimes.max(), hi > lo else { return 0...1 }
        return lo...hi
    }
    private var valueRange: ClosedRange<Double> {
        guard let hi = allValues.max(), hi > 0 else { return 0...1 }
        return 0...hi
    }

    private func point(time: Double, value: Double, in plot: CGRect) -> CGPoint {
        let tSpan = timeRange.upperBound - timeRange.lowerBound
        let vSpan = valueRange.upperBound - valueRange.lowerBound
        let xf = tSpan > 0 ? (time - timeRange.lowerBound) / tSpan : 0.5
        let yf = vSpan > 0 ? (value - valueRange.lowerBound) / vSpan : 0
        return CGPoint(x: plot.minX + CGFloat(xf) * plot.width,
                        y: plot.maxY - CGFloat(yf) * plot.height)
    }

    /// Every segment's true color when the read is trustworthy; a single flat grey when
    /// it isn't — de-emphasizing the picture rather than asserting an order it can't back.
    private func markColor(_ segment: KinematicSequence.Segment) -> Color {
        guard trustworthy else { return .ink25 }
        switch segment {
        case .pelvis: return .ink70
        case .torso: return .fairwayDeep
        case .leadArm: return .amber
        case .club: return .brickText
        }
    }

    // MARK: verdict / caution

    @ViewBuilder
    private var verdict: some View {
        if trustworthy {
            HStack(spacing: 7) {
                ZStack {
                    Circle().fill(sequence.isInOrder ? Color.fairwayDeep : Color.brick)
                        .frame(width: 16, height: 16)
                    if sequence.isInOrder {
                        CheckGlyph()
                            .stroke(Color.paper, style: .init(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                            .frame(width: 7, height: 6)
                    } else {
                        BangGlyph()
                            .stroke(Color.paper, style: .init(lineWidth: 1.6, lineCap: .round))
                            .frame(width: 2, height: 8)
                    }
                }
                MicroLabel(sequence.isInOrder ? "In order" : "Out of order",
                           color: sequence.isInOrder ? .fairwayText : .brickText)
            }
            .accessibilityIdentifier("sequenceOrderVerdict")
        } else {
            Text("Body rotation was too unsteady at the top to judge the order")
                .font(Type.ui(12.5))
                .lineSpacing(2.5)
                .foregroundStyle(Color.ink45)
                .accessibilityIdentifier("sequenceCautionCaption")
        }
    }
}

private extension KinematicSequence.Segment {
    var stairLabel: String {
        switch self {
        case .pelvis: return "Pelvis"
        case .torso: return "Torso"
        case .leadArm: return "Arms"
        case .club: return "Club"
        }
    }
}
