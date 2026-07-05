// The analysis screen — the heart of the app. Editorial layout per the reference
// prototype: header, dated headline, hero card (Video / 3D / Split + checkpoint
// scrubber), tappable marker detail, score + verdict, metric meters, prioritized goals.
import SwiftUI
import SwingKit

struct AnalysisScreen: View {
    @Bindable var model: AnalysisModel
    @State private var enhancedCoaching = EnhancedCoachingStore.shared
    var onBack: (() -> Void)? = nil
    var onRecord: () -> Void = {}
    /// Most recent prior swing of the SAME club AND view, resolved by RootView from the
    /// swing history. Drives the current-vs-previous deltas. nil when there is none.
    var priorReport: SwingReport? = nil
    /// Recent same-club swings in chronological order (oldest first, current last), for
    /// measured fault-fixed / improving detection on the lead card.
    var clubHistory: [SwingReport] = []

    var body: some View {
        ZStack {
            Color.bone.grain().ignoresSafeArea()
            ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    heading.padding(.top, 36)
                    heroCard.padding(.top, 20)

                    if LeadCard.shouldShow(for: model.report) {
                        LeadCard(report: model.report, priorReport: priorReport, history: clubHistory)
                            .padding(.top, 20)
                    }

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

                    if let scoreDelta {
                        scoreDeltaBadge(scoreDelta).padding(.top, 10)
                    }

                    if let warnings = model.report.quality?.warnings, !warnings.isEmpty,
                       model.report.score.availability != .insufficientData {
                        // When the score is insufficient the LeadCard already lists these
                        // warnings up top, so this lower "notes" card would just repeat them.
                        FloatCard(padding: 18) {
                            VStack(alignment: .leading, spacing: 7) {
                                MicroLabel("Measurement notes", color: .brickText)
                                ForEach(warnings, id: \.self) { warning in
                                    Text(warning)
                                        .font(Type.ui(12.5))
                                        .foregroundStyle(Color.ink70)
                                }
                            }
                        }
                        .padding(.top, 18)
                    }

                    Hairline().padding(.top, 32)
                        .id("metrics")

                    MetricsSection(report: model.report, priorReport: priorReport)
                        .padding(.top, 8)

                    goals.padding(.top, 40)

                    PrimaryButton("Record next swing", action: onRecord)
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
        .task(id: model.report.id) { await enhancedCoaching.enhance(model) }
        .onDisappear { enhancedCoaching.cancel(reportID: model.report.id) }
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
            TimelineScrubber(model: model)
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
        }
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.paper))
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .floatShadow()
    }

    // One persistent video view + one avatar pane, resized between modes — never
    // recreated, so pane switches glide with no blank player flash.
    private var videoHeight: CGFloat {
        switch model.pane { case .video: 400; case .split: 224; case .avatar: 0 }
    }
    private var avatarHeight: CGFloat {
        switch model.pane { case .avatar: 400; case .split: 176; case .video: 0 }
    }

    private var panes: some View {
        VStack(spacing: 0) {
            VideoAnalysisView(model: model)
                .frame(height: videoHeight)
                .clipped()
                .opacity(videoHeight > 0 ? 1 : 0)
            Hairline()
                .opacity(model.pane == .split ? 1 : 0)
            if model.pane != .video {
                AvatarPane(model: model, compact: model.pane == .split)
                    .frame(height: avatarHeight)
                    .clipped()
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.88), value: model.pane)
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

    // MARK: score delta (current vs previous)

    private var scoreDelta: Int? {
        guard let priorReport else { return nil }
        return SwingComparison.scoreDelta(current: model.report, previous: priorReport)
    }

    private func scoreDeltaBadge(_ value: Int) -> some View {
        let color: Color = value > 0 ? .fairwayText : value < 0 ? .brickText : .ink45
        let arrow = value > 0 ? "▲" : value < 0 ? "▼" : "•"
        let sign = value > 0 ? "+" : ""
        return HStack(spacing: 7) {
            MicroLabel("vs last swing", color: .ink45)
            Text("\(arrow) \(sign)\(value)")
                .font(Type.ui(11, .bold))
                .foregroundStyle(color)
        }
    }

    // MARK: goals

    @ViewBuilder
    private var goals: some View {
        if let coaching = model.report.coaching, !coaching.goals.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    MicroLabel("Your Goals")
                    Spacer()
                    MicroLabel(coachingLabel, color: .ink25)
                }
                ForEach(Array(coaching.goals.enumerated()), id: \.element.id) { i, g in
                    GoalCard(goal: g, index: i)
                }
            }
        }
    }

    private var coachingLabel: String {
        switch enhancedCoaching.state(for: model.report.id) {
        case .local: "Local coaching"
        case .enhancing: "Enhancing…"
        case .enhanced: "Enhanced coaching"
        }
    }
}

/// The 3D pane: the sculpted avatar driven by the same timeline as the video.
struct AvatarPane: View {
    @Bindable var model: AnalysisModel
    var compact: Bool = false

    var body: some View {
        ZStack {
            Color.paper
            AvatarView(
                frames: model.report.frames,
                time: $model.time,
                isPlaying: model.isPlaying,
                showPlane: !compact,
                showPath: true,
                orbitEnabled: !compact
            )
            if compact {
                VStack {
                    Spacer()
                    HStack {
                        MicroLabel("3D · From your tracks", color: .ink45, size: 8.5)
                            .scrimChip()
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
            }
        }
    }
}
