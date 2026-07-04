// Components of the analysis screen: pane toggle, checkpoint scrubber, marker detail,
// metric meters, score block, goal cards. Visual spec: reference/src/App.tsx.
import SwiftUI
import SwingKit

// MARK: - Pane toggle (Video / 3D / Split)

struct PaneToggle: View {
    @Binding var pane: AnalysisPane
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AnalysisPane.allCases) { p in
                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) { pane = p }
                } label: {
                    Text(p.label.uppercased())
                        .font(Type.ui(10, .bold))
                        .tracking(1.2)
                        .foregroundStyle(pane == p ? Color.bone : Color.ink45)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background {
                            if pane == p {
                                Capsule().fill(Color.ink)
                                    .matchedGeometryEffect(id: "pane-pill", in: ns)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.bone.opacity(0.85)))
    }
}

// MARK: - Checkpoint scrubber

struct CheckpointScrubber: View {
    @Bindable var model: AnalysisModel
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            playButton
            ForEach(model.headline, id: \.self) { p in
                Button {
                    model.select(p)
                } label: {
                    VStack(spacing: 4) {
                        Text(p.name == "Follow-Through" || p.name == "Finish" ? "Follow" : p.name)
                            .font(Type.ui(12, .medium))
                            .tracking(0.3)
                            .foregroundStyle(model.selectedPosition == p ? Color.ink : Color.ink25)
                        ZStack {
                            Color.clear.frame(height: 2)
                            if model.selectedPosition == p {
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.fairwayDeep)
                                    .frame(height: 2)
                                    .padding(.horizontal, 10)
                                    .matchedGeometryEffect(id: "kf", in: ns)
                            }
                        }
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: model.selectedPosition)
    }

    private var playButton: some View {
        Button(action: model.togglePlay) {
            ZStack {
                Circle().fill(Color.ink).frame(width: 30, height: 30)
                if model.isPlaying {
                    PauseGlyph().fill(Color.bone).frame(width: 9, height: 10)
                } else {
                    PlayGlyph().fill(Color.bone).frame(width: 9, height: 10).offset(x: 0.8)
                }
            }
            .frame(width: 52, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
    }
}

// MARK: - Marker detail card

struct MarkerDetailCard: View {
    let marker: SwingMarker
    let onClose: () -> Void

    private var color: Color { marker.kind == .good ? .fairwayDeep : .brick }
    private var labelColor: Color { marker.kind == .good ? .fairwayText : .brickText }

    var body: some View {
        FloatCard(padding: 20) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(color).frame(width: 18, height: 18)
                    if marker.kind == .good {
                        CheckGlyph().stroke(Color.paper, style: .init(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                            .frame(width: 8, height: 7)
                    } else {
                        BangGlyph().stroke(Color.paper, style: .init(lineWidth: 1.8, lineCap: .round))
                            .frame(width: 2, height: 9)
                    }
                }
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        MicroLabel(marker.kind == .good ? "Working" : "Needs work", color: labelColor)
                        Spacer()
                        Button(action: onClose) {
                            CrossGlyph().stroke(Color.ink25, style: .init(lineWidth: 1.6, lineCap: .round))
                                .frame(width: 9, height: 9)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .offset(x: 8, y: -6)
                    }
                    Text(marker.title)
                        .font(Type.display(20))
                        .foregroundStyle(Color.ink)
                        .padding(.top, 2)
                    Text(marker.detail)
                        .font(Type.ui(13.5))
                        .lineSpacing(3.5)
                        .foregroundStyle(Color.ink70)
                        .padding(.top, 7)
                }
            }
        }
    }
}

// MARK: - Metric meter

struct MeterRow: View {
    let m: MetricValue

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                MicroLabel(m.label)
                Spacer()
                (Text(trimmed(m.value)).foregroundStyle(Color.ink)
                    + Text(m.unit).font(Type.display(15)).foregroundStyle(Color.ink45))
                    .font(Type.display(26))
            }
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.ink08).frame(height: 3)
                    Capsule().fill(Color.fairway.opacity(0.45))
                        .frame(width: max(0, (m.bandFill.upperBound - m.bandFill.lowerBound)) * w, height: 3)
                        .offset(x: m.bandFill.lowerBound * w)
                    Circle()
                        .fill(m.inBand ? Color.fairwayDeep : Color.ink)
                        .stroke(Color.bone, lineWidth: 1.5)
                        .frame(width: 10, height: 10)
                        .offset(x: m.fill * w - 5)
                }
            }
            .frame(height: 10)
        }
        .padding(.vertical, 18)
    }

    private func trimmed(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}

// MARK: - Score block

struct ScoreBlock: View {
    let score: SwingScore
    let verdict: String?

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                MicroLabel("Swing Score")
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(score.total)")
                        .font(Type.display(72))
                        .foregroundStyle(Color.ink)
                    Text("/100")
                        .font(Type.display(24))
                        .foregroundStyle(Color.ink25)
                }
            }
            Spacer(minLength: 24)
            if let verdict {
                Text(verdict)
                    .font(Type.displayItalic(19))
                    .foregroundStyle(Color.ink70)
                    .multilineTextAlignment(.trailing)
                    .lineSpacing(2)
                    .frame(maxWidth: 170, alignment: .trailing)
                    .padding(.top, 6)
            }
        }
    }
}

// MARK: - Goal card

struct GoalCard: View {
    let goal: CoachGoal
    let index: Int

    var body: some View {
        FloatCard(padding: 24) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    Text("\(index + 1)")
                        .font(Type.display(30))
                        .foregroundStyle(Color.ink25)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        MicroLabel(goal.metricLabel)
                        Text(goal.title)
                            .font(Type.display(22))
                            .foregroundStyle(Color.ink)
                    }
                }
                Text(goal.detail)
                    .font(Type.ui(13.5))
                    .lineSpacing(3.5)
                    .foregroundStyle(Color.ink70)
                    .padding(.top, 12)

                HStack(spacing: 12) {
                    Text(goal.current)
                        .font(Type.ui(11, .medium))
                        .foregroundStyle(Color.ink70)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(Color.sand))
                    Text("→")
                        .font(Type.ui(12))
                        .foregroundStyle(Color.ink25)
                    Text(goal.target)
                        .font(Type.ui(11, .bold))
                        .foregroundStyle(Color.fairwayText)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(Color.fairway.opacity(0.2)))
                }
                .padding(.top, 18)

                VStack(alignment: .leading, spacing: 4) {
                    Hairline()
                    MicroLabel("Drill", color: .ink45)
                        .padding(.top, 10)
                    (Text(goal.drill).font(Type.ui(13, .medium))
                        + Text(" — \(goal.drillDetail)").font(Type.ui(13)))
                        .foregroundStyle(Color.ink)
                        .lineSpacing(2.5)
                }
                .padding(.top, 16)
            }
        }
    }
}
