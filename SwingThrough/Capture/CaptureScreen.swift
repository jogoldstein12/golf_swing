// Capture flow entry. Reached via ST_SCREEN=capture (see RootView) or the app's
// "Record next swing" action. Guided setup → auto swing detection → review → hand the
// trimmed clip to the analysis pipeline through `onCaptured`.
//
// Dev harness: ST_FEED=file swaps the camera for the bundled DTL fixture, paced to the
// wall clock — the full idle → ready → capturing → captured cycle runs in the Simulator.
import SwiftUI
import SwingKit

struct CaptureScreen: View {
    var onCaptured: (URL, CaptureView) -> Void = { _, _ in }

    @StateObject private var controller = CaptureController()
    @State private var showSetupSheet = false

    init(onCaptured: @escaping (URL, CaptureView) -> Void = { _, _ in }) {
        self.onCaptured = onCaptured
    }

    var body: some View {
        ZStack {
            Color.bone.grain().ignoresSafeArea()

            switch controller.screen {
            case .starting:
                startingState
            case .live:
                liveLayout
            case .review(let take):
                reviewLayout(take)
            case .denied:
                EmptyFeedState(
                    headline: "The camera is off.",
                    body: "Swing Through measures your swing from video, so it needs "
                        + "the camera. Everything is analyzed on this phone — nothing "
                        + "leaves it.",
                    actionTitle: "Open Settings",
                    action: openSettings)
            case .unavailable(let why):
                EmptyFeedState(
                    headline: "No camera here.",
                    body: "This device has no camera feed. On the Simulator, launch "
                        + "with ST_FEED=file to drive capture from the bundled swing. "
                        + "(\(why))",
                    actionTitle: nil,
                    action: {})
            }
        }
        .sheet(isPresented: $showSetupSheet) {
            SetupSheet(angle: controller.angle)
        }
        .onAppear {
            controller.start()
            runDemoScript()
        }
        .onDisappear { controller.stopFeed() }
    }

    /// Dev harness only: ST_DEMO="delay:action,delay:action,…" drives the interactive
    /// paths sequentially (the CI/Simulator loop has no way to tap the screen).
    /// Actions: faceon · dtl · help · helpclose · countdown · retake · accept.
    /// retake/accept first wait until a review card is actually showing.
    private func runDemoScript() {
        guard let script = ProcessInfo.processInfo.environment["ST_DEMO"],
              !script.isEmpty else { return }
        let steps: [(Double, String)] = script.split(separator: ",").compactMap {
            let bits = $0.split(separator: ":")
            guard bits.count == 2, let d = Double(bits[0]) else { return nil }
            return (d, String(bits[1]))
        }
        Task { @MainActor in
            for (delay, action) in steps {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                switch action {
                case "faceon": controller.setAngle(.faceOn)
                case "dtl": controller.setAngle(.downTheLine)
                case "help": showSetupSheet = true
                case "helpclose": showSetupSheet = false
                case "countdown": controller.beginCountdown()
                case "retake":
                    await waitForReview()
                    controller.retake()
                case "accept":
                    await waitForReview()
                    controller.accept(onCaptured: onCaptured)
                default: break
                }
            }
        }
    }

    @MainActor
    private func waitForReview() async {
        while true {
            if case .review = controller.screen { return }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    private var startingState: some View {
        VStack(spacing: 14) {
            MicroLabel("Capture")
            Text("Opening the camera…")
                .font(Type.displayItalic(19))
                .foregroundStyle(Color.ink45)
        }
    }

    // MARK: - Live

    private var liveLayout: some View {
        VStack(spacing: 0) {
            header(title: controller.angle == .downTheLine ? "Down the line" : "Face on",
                   kicker: "Capture")

            previewCard
                .padding(.horizontal, 24)
                .padding(.top, 14)

            VStack(spacing: 12) {
                ChecklistChips(checklist: controller.checklist)
                Text(controller.cue)
                    .font(Type.displayItalic(16))
                    .foregroundStyle(Color.ink45)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: controller.cue)
            }
            .padding(.top, 16)
            .padding(.bottom, 10)
            .padding(.horizontal, 24)
        }
    }

    private func header(title: String, kicker: String) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                MicroLabel(kicker)
                Text(title)
                    .font(Type.display(30))
                    .foregroundStyle(Color.ink)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: title)
            }
            Spacer()
            Button {
                showSetupSheet = true
            } label: {
                ZStack {
                    Circle().strokeBorder(Color.ink25, lineWidth: 1)
                    Text("?")
                        .font(Type.display(17))
                        .foregroundStyle(Color.ink70)
                        .baselineOffset(-1)
                }
                .frame(width: 34, height: 34)
                .contentShape(Circle())
            }
            .buttonStyle(PressScaleStyle())
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    private var previewCard: some View {
        GeometryReader { geo in
            let fitted = fittedVideoSize(in: geo.size)
            ZStack {
                FeedPreviewView(sink: controller.previewSink)

                // Edge scrims for chrome legibility — a whisper, not a vignette.
                LinearGradient(
                    colors: [Color.ink.opacity(0.22), .clear],
                    startPoint: .top, endPoint: .init(x: 0.5, y: 0.28))
                LinearGradient(
                    colors: [.clear, Color.ink.opacity(0.18)],
                    startPoint: .init(x: 0.5, y: 0.72), endPoint: .bottom)

                if showGuides {
                    FramingGuides(angle: controller.angle, armed: isArmed)
                    GuideLabels(angle: controller.angle)
                        .transition(.opacity)
                }

                if !controller.displayJoints.isEmpty {
                    SkeletonOverlay(joints: controller.displayJoints)
                        .transition(.opacity)
                }

                chrome

                if let count = controller.countdown {
                    CountdownOverlay(count: count)
                }
                if controller.exporting {
                    exportingVeil
                }
            }
            .frame(width: fitted.width, height: fitted.height)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .floatShadowLarge()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var showGuides: Bool {
        switch controller.phase {
        case .idle, .ready: true
        case .capturing, .settling, .captured: false
        }
    }

    private var isArmed: Bool {
        if case .ready = controller.phase { return true }
        return false
    }

    private var canUseManual: Bool {
        switch controller.phase {
        case .idle, .ready: true
        default: false
        }
    }

    private var chrome: some View {
        VStack {
            HStack(alignment: .top) {
                CaptureStatusBadge(phase: controller.phase)
                Spacer()
                AngleSelector(angle: controller.angle) { controller.setAngle($0) }
            }
            .padding(14)
            Spacer()
            if canUseManual {
                RecordButton(counting: controller.countdown != nil) {
                    if controller.countdown != nil {
                        controller.cancelCountdown()
                    } else {
                        controller.beginCountdown()
                    }
                }
                .padding(.bottom, 18)
                .transition(.opacity.combined(with: .scale(scale: 0.86)))
            }
        }
    }

    private var exportingVeil: some View {
        ZStack {
            Color.ink.opacity(0.25)
            VStack(spacing: 10) {
                MicroLabel("Saving", color: .bone, size: 11)
                Text("Trimming your swing…")
                    .font(Type.displayItalic(18))
                    .foregroundStyle(Color.bone)
            }
        }
        .transition(.opacity)
    }

    private func fittedVideoSize(in container: CGSize) -> CGSize {
        let aspect = controller.feedAspect
        guard container.width > 0, container.height > 0 else { return container }
        let widthBound = CGSize(width: container.width,
                                height: container.width / aspect)
        if widthBound.height <= container.height { return widthBound }
        return CGSize(width: container.height * aspect, height: container.height)
    }

    // MARK: - Review

    private func reviewLayout(_ take: CaptureTake) -> some View {
        VStack(spacing: 0) {
            header(title: "Review", kicker: "Swing captured")

            GeometryReader { geo in
                let fitted = fittedVideoSize(in: geo.size)
                LoopingPlayerView(url: take.url)
                    .frame(width: fitted.width, height: fitted.height)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card,
                                                style: .continuous))
                    .floatShadowLarge()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))

            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    MicroLabel(take.view == .downTheLine ? "Down the line" : "Face on",
                               color: .ink70)
                    MicroLabel("·", color: .ink25)
                    MicroLabel("\(Int(take.fps.rounded())) fps", color: .ink70)
                    MicroLabel("·", color: .ink25)
                    MicroLabel(String(format: "%.1f s", take.duration), color: .ink70)
                }
                PrimaryButton("Analyze swing") {
                    controller.accept(onCaptured: onCaptured)
                }
                Button {
                    controller.retake()
                } label: {
                    Text("Retake")
                        .font(Type.ui(13, .medium))
                        .tracking(0.3)
                        .foregroundStyle(Color.ink45)
                        .padding(.vertical, 2)
                }
                .buttonStyle(PressScaleStyle())
            }
            .padding(.top, 16)
            .padding(.bottom, 10)
            .padding(.horizontal, 24)
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Designed empty state (denied / no feed)

private struct EmptyFeedState: View {
    let headline: String
    let message: String
    let actionTitle: String?
    let action: () -> Void

    init(headline: String, body: String, actionTitle: String?,
         action: @escaping () -> Void) {
        self.headline = headline
        self.message = body
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            NoCameraGlyph()
            MicroLabel("Camera access")
                .padding(.top, 28)
            Text(headline)
                .font(Type.display(32))
                .foregroundStyle(Color.ink)
                .padding(.top, 10)
            Text(message)
                .font(Type.ui(13.5))
                .lineSpacing(4)
                .foregroundStyle(Color.ink70)
                .padding(.top, 12)
            if let actionTitle {
                PrimaryButton(actionTitle, action: action)
                    .padding(.top, 28)
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
    }
}

#Preview {
    CaptureScreen()
}
