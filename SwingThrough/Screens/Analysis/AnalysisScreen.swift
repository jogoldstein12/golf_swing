// The analysis screen — the heart of the app. Editorial layout per the reference
// prototype: header, dated headline, hero card (Video / 3D / Split + checkpoint
// scrubber), tappable marker detail, score + verdict, metric meters, prioritized goals.
import SwiftUI
import SwingKit

struct AnalysisScreen: View {
    @Bindable var model: AnalysisModel
    @State private var enhancedCoaching = EnhancedCoachingStore.shared
    /// "More lines" disclosure for the plane overlay — shared between the video-space
    /// PlaneOverlay (drawn in the hero card) and CoachingCanvas's toggle button below it,
    /// so the two views can never disagree about what's drawn.
    @State private var showAdvancedOverlay = false
    var onBack: (() -> Void)? = nil
    var onRecord: () -> Void = {}
    /// Open the drill-detail (practice loop) page for a goal. Wired by RootView.
    var onOpenDrill: (CoachGoal) -> Void = { _ in }
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
                    GlanceStrip(
                        score: model.report.score,
                        oneThing: model.report.coaching?.goals.first?.title,
                        scoreDelta: scoreDelta
                    )
                    .padding(.top, 20)
                    heading.padding(.top, 30)
                    heroCard.padding(.top, 20)

                    // The coaching canvas leads for a SCORED read: goal #1's honest overlay
                    // (drawn on the actual video frame above, in the hero card) + one cue
                    // + the two next actions. Never shown for a low-confidence read —
                    // there is no trustworthy fault to draw.
                    if let plan = overlayPlan {
                        CoachingCanvas(
                            plan: plan,
                            drillName: model.report.coaching?.goals.first?.drill,
                            onSeeFix: { model.select(plan.position) },
                            onDrill: {
                                if let goal = model.report.coaching?.goals.first { onOpenDrill(goal) }
                            },
                            showAdvanced: $showAdvancedOverlay
                        )
                        .padding(.top, 20)
                    }

                    // The low-confidence lead still leads when the read was too limited to
                    // score; the scored case is now carried by the glance strip + canvas.
                    if !model.report.score.isAvailable, LeadCard.shouldShow(for: model.report) {
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
            ZStack(alignment: .topLeading) {
                VideoAnalysisView(model: model)
                if videoHeight > 0 { planeOverlayLayer }
            }
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

    /// The goal overlay, riding in the SAME cover-scale + per-time window container the
    /// video itself uses (VideoPaneLayout + the model's own framing track) — one source
    /// of truth, so the drawing can never drift from the pixels the video shows.
    private var planeOverlayLayer: some View {
        GeometryReader { geo in
            let layout = VideoPaneLayout(pane: geo.size, videoSize: model.videoSize)
            let windowTop = model.framingWindowTop(at: model.time, visible: layout.visibleFraction)
            let offsetY = layout.offsetY(forWindowTop: windowTop)

            PlaneOverlay(
                plan: overlayPlan,
                planeLine2D: model.report.plane.basePlaneLine2D,
                videoSize: honestVideoSize,
                isEstimated: overlayIsEstimated,
                showAdvanced: showAdvancedOverlay
            )
            .frame(width: layout.displaySize.width, height: layout.displaySize.height, alignment: .topLeading)
            .offset(y: -offsetY)
            .animation(model.isPlaying ? nil : .spring(response: 0.55, dampingFraction: 0.9), value: offsetY)
        }
        .allowsHitTesting(false)
    }

    // MARK: goal overlay resolution

    /// Goal #1's honest overlay plan — used both by the video-space PlaneOverlay (drawn
    /// above, in the hero card) and CoachingCanvas's caption/controls band below it. One
    /// plan, two views: they can never disagree about what's drawn.
    private var overlayPlan: OverlayPlan? {
        guard let goal = model.report.coaching?.goals.first, model.report.score.isAvailable else {
            return nil
        }
        return SwingOverlay.plan(goal: goal, report: model.report, prior: priorReport, skill: .beginner)
    }

    /// True when the plane goal's own metric is not a confident `.measured` read — the
    /// overlay then draws dashed/amber and is captioned "Estimated", never the raw
    /// pipeline word ("inferred" / "interpolated").
    private var overlayIsEstimated: Bool {
        guard let goal = model.report.coaching?.goals.first else { return false }
        let provenance = model.report.coachableMetric(for: goal)?.quality?.provenance ?? .measured
        return provenance != .measured
    }

    /// The pipeline's own video pixel dimensions. nil is an honest gate: without them
    /// the overlay's normalized -> pixel mapping can't be trusted, so it draws nothing.
    private var honestVideoSize: CGSize? {
        guard let w = model.report.videoWidth, let h = model.report.videoHeight else { return nil }
        return CGSize(width: w, height: h)
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
        // Goal #1 is surfaced above by the glance strip + coaching canvas, so the list
        // shows the remaining goals only (keeping their original 2, 3… numbering).
        if let coaching = model.report.coaching, coaching.goals.count > 1 {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    MicroLabel("The rest of your plan")
                    Spacer()
                    MicroLabel(coachingLabel, color: .ink25)
                }
                ForEach(Array(coaching.goals.enumerated()).dropFirst(), id: \.element.id) { i, g in
                    GoalCard(goal: g, index: i, onDrill: { onOpenDrill(g) })
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
