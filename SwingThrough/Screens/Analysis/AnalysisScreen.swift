// The analysis screen — the heart of the app. Editorial layout per the reference
// prototype: header, dated headline, hero card (Video / 3D / Split + checkpoint
// scrubber), tappable marker detail, score + verdict, metric meters, prioritized goals.
import SwiftUI
import SwingKit

struct AnalysisScreen: View {
    @Bindable var model: AnalysisModel
    var onBack: (() -> Void)? = nil

    var body: some View {
        ZStack {
            Color.bone.grain().ignoresSafeArea()
            ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    heading.padding(.top, 36)
                    heroCard.padding(.top, 20)

                    if let marker = model.selectedMarker {
                        MarkerDetailCard(marker: marker) {
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                                model.selectedMarker = nil
                            }
                        }
                        .padding(.top, 16)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: -8)).combined(with: .scale(scale: 0.98, anchor: .top)),
                            removal: .opacity.combined(with: .offset(y: -6))
                        ))
                        .id(marker.id)
                    }

                    ScoreBlock(score: model.report.score, verdict: model.report.coaching?.verdict)
                        .padding(.top, 40)

                    Hairline().padding(.top, 32)
                        .id("metrics")

                    metrics.padding(.top, 8)

                    goals.padding(.top, 40)

                    PrimaryButton("Record next swing") {}
                        .padding(.top, 36)
                        .id("bottom")
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 40)
            }
            .onAppear {
                // Dev hook: ST_SCROLL=bottom|metrics jumps for screenshot runs.
                if let target = ProcessInfo.processInfo.environment["ST_SCROLL"] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.9)) {
                            proxy.scrollTo(target == "bottom" ? "bottom" : "metrics", anchor: target == "bottom" ? .bottom : .top)
                        }
                    }
                }
            }
            }
        }
    }

    // MARK: header + heading

    private var header: some View {
        HStack {
            if let onBack {
                Button(action: onBack) {
                    HStack(spacing: 9) {
                        ZStack {
                            Circle().strokeBorder(Color.ink25, lineWidth: 1)
                            ChevronGlyph(pointsRight: false)
                                .stroke(Color.ink70, style: .init(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                                .frame(width: 6, height: 11)
                        }
                        .frame(width: 32, height: 32)
                        MicroLabel("Swings", color: .ink70)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle())
            } else {
                Text("Swing Through")
                    .font(Type.display(23))
                    .foregroundStyle(Color.ink)
            }
            Spacer()
            MicroLabel(model.report.club, color: .ink70)
            Circle().fill(Color.ink).frame(width: 26, height: 26)
        }
    }

    private var heading: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                MicroLabel("Swing Analysis")
                headlineDate
            }
            Spacer()
            MicroLabel(model.report.date.formatted(.dateTime.day(.twoDigits)) + " · "
                       + model.report.date.formatted(.dateTime.month(.twoDigits)))
                .padding(.bottom, 4)
        }
    }

    private var headlineDate: some View {
        let date = model.report.date
        let day = Calendar.current.isDateInToday(date) ? "Today"
            : Calendar.current.isDateInYesterday(date) ? "Yesterday"
            : date.formatted(.dateTime.weekday(.wide))
        let f = DateFormatter()
        f.dateFormat = "h:mm"
        let ampm = Calendar.current.component(.hour, from: date) < 12 ? " am" : " pm"
        return (Text("\(day), \(f.string(from: date))").foregroundStyle(Color.ink)
            + Text(ampm).foregroundStyle(Color.ink25))
            .font(Type.display(34))
    }

    // MARK: hero card

    private var heroCard: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                panes
                paneChrome
            }
            Hairline()
            CheckpointScrubber(model: model)
                .padding(.horizontal, 8)
        }
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.paper))
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .floatShadow()
    }

    @ViewBuilder
    private var panes: some View {
        switch model.pane {
        case .video:
            VideoAnalysisView(model: model)
                .frame(height: 400)
        case .avatar:
            AvatarPane(model: model)
                .frame(height: 400)
        case .split:
            VStack(spacing: 0) {
                VideoAnalysisView(model: model)
                    .frame(height: 224)
                Hairline()
                AvatarPane(model: model, compact: true)
                    .frame(height: 176)
            }
        }
    }

    private var paneChrome: some View {
        HStack(alignment: .center) {
            HStack(spacing: 7) {
                Circle().fill(Color.fairwayDeep).frame(width: 6, height: 6)
                MicroLabel(positionLabel, color: .ink70)
            }
            .scrimChip()
            Spacer()
            PaneToggle(pane: $model.pane)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private var positionLabel: String {
        let p = model.selectedPosition
        return "\(p.name) · \(p.shortName)"
    }

    // MARK: metrics + goals

    private var metrics: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.report.metrics.enumerated()), id: \.element.label) { i, m in
                if i > 0 { Hairline() }
                MeterRow(m: m)
            }
        }
    }

    @ViewBuilder
    private var goals: some View {
        if let coaching = model.report.coaching, !coaching.goals.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    MicroLabel("Your Goals")
                    Spacer()
                    MicroLabel("Priority order", color: .ink25)
                }
                ForEach(Array(coaching.goals.enumerated()), id: \.element.id) { i, g in
                    GoalCard(goal: g, index: i)
                }
            }
        }
    }
}

/// 3D pane placeholder until the avatar module lands; then it hosts AvatarView.
struct AvatarPane: View {
    let model: AnalysisModel
    var compact: Bool = false

    var body: some View {
        ZStack {
            Color.paper
            VStack(spacing: 10) {
                MicroLabel("3D avatar", color: .ink25)
                if !compact {
                    Text("Sculpting…")
                        .font(Type.displayItalic(17))
                        .foregroundStyle(Color.ink25)
                }
            }
        }
    }
}
