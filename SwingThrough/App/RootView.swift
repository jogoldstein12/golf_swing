// App root: Home (gallery) → Analysis, with capture as a full-screen cover and the
// analyzing run bridging the two. Dev routing via env vars lets any surface be
// screenshot directly: ST_SCREEN=avatar|capture|analysis|settings|analyzing,
// ST_POS=p1..p10, ST_SCROLL=metrics|bottom.
import SwiftData
import SwiftUI
import SwingKit

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SwingRecord.date, order: .reverse) private var swings: [SwingRecord]

    enum Route: Hashable { case drills }

    @State private var path = NavigationPath()
    @State private var showCapture = false
    @State private var session = SwingSession()
    let startupWarning: String?

    @State private var demoAnalysis: AnalysisModel? = {
        guard let demo = DemoData.load() else { return nil }
        return AnalysisModel(report: demo.report, videoURL: demo.videoURL, videoSize: demo.videoSize)
    }()

    init(startupWarning: String? = nil) {
        self.startupWarning = startupWarning
    }

    var body: some View {
        let env = ProcessInfo.processInfo.environment
        switch env["ST_SCREEN"] {
        case "avatar": AvatarPreviewScreen()
        case "capture": CaptureScreen()
        case "analysis": demoAnalysisView
        case "settings": SettingsSheet()
        case "drills": DrillsScreen()
        case "analyzing": AnalyzingScreen(progress: 0.55, phase: "Measuring plane and sequence")
        default:
            if env["ST_POS"] != nil || env["ST_SCROLL"] != nil {
                demoAnalysisView
            } else {
                main
            }
        }
    }

    private var main: some View {
        NavigationStack(path: $path) {
            HomeScreen(
                onRecord: { showCapture = true },
                onImport: { analyze($0, view: .downTheLine) },
                onOpen: { path.append($0) },
                onDrills: { path.append(Route.drills) }
            )
            .navigationDestination(for: SwingRecord.self) { record in
                if let model = SwingStore.analysisModel(for: record) {
                    AnalysisScreen(model: model, onBack: { path.removeLast() }, onRecord: recordNextSwing)
                        .navigationBarBackButtonHidden(true)
                        .toolbar(.hidden, for: .navigationBar)
                } else {
                    unavailableAnalysis(onBack: { path.removeLast() })
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .drills:
                    DrillsScreen(onBack: { path.removeLast() })
                        .navigationBarBackButtonHidden(true)
                        .toolbar(.hidden, for: .navigationBar)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            // Dev hook: ST_RUN_SAMPLE=1 pushes the bundled clip through the real
            // analyze→coach→store chain, as if it had just been captured.
            if ProcessInfo.processInfo.environment["ST_RUN_SAMPLE"] != nil,
               let url = Bundle.main.url(forResource: "sample_dtl", withExtension: "mp4") {
                if let record = await session.run(url: url, view: .downTheLine, club: "7 Iron",
                                                  context: modelContext, history: swings) {
                    path.append(record)
                }
            }
        }
        .fullScreenCover(isPresented: $showCapture) {
            CaptureScreen(onCancel: { showCapture = false }, onCaptured: { url, view in
                showCapture = false
                analyze(url, view: view)
            })
        }
        .overlay {
            switch session.phase {
            case .running(let progress, let label):
                AnalyzingScreen(progress: progress, phase: label)
                    .transition(.opacity)
            case .failed(let message):
                analysisFailure(message)
                    .transition(.opacity)
            case .idle:
                EmptyView()
            }
        }
        .animation(.easeInOut(duration: 0.35), value: isRunning)
        .safeAreaInset(edge: .top, spacing: 0) {
            if let startupWarning {
                Text(startupWarning)
                    .font(Type.ui(11, .medium))
                    .foregroundStyle(Color.bone)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.brickText)
            }
        }
    }

    @ViewBuilder
    private var demoAnalysisView: some View {
        if let demoAnalysis {
            AnalysisScreen(model: demoAnalysis)
        } else {
            unavailableAnalysis(onBack: nil)
        }
    }

    private func analyze(_ url: URL, view: CaptureView) {
        Task {
            let record = await session.run(url: url, view: view, club: "7 Iron",
                                           context: modelContext, history: swings)
            removeWorkingVideoIfNeeded(url)
            if let record { path.append(record) }
        }
    }

    private func recordNextSwing() {
        if !path.isEmpty { path.removeLast() }
        showCapture = true
    }

    private func removeWorkingVideoIfNeeded(_ url: URL) {
        let path = url.standardizedFileURL.path
        let temporary = FileManager.default.temporaryDirectory.standardizedFileURL.path
        let swings = SwingStore.swingsDirectory.standardizedFileURL.path
        if path.hasPrefix(temporary + "/")
            || (path.hasPrefix(swings + "/") && url.lastPathComponent.hasPrefix("swing-")) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private var isRunning: Bool {
        if case .idle = session.phase { return false }
        return true
    }

    private func analysisFailure(_ message: String) -> some View {
        ZStack {
            Color.bone.grain().ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                FloatCard(padding: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        MicroLabel("Couldn't measure that one", color: .brickText)
                        Text("The swing didn't track.")
                            .font(Type.display(24))
                            .foregroundStyle(Color.ink)
                        Text(message)
                            .font(Type.ui(13))
                            .lineSpacing(3)
                            .foregroundStyle(Color.ink70)
                        Text("Full body in frame, steady phone, and good light make the difference.")
                            .font(Type.ui(13))
                            .lineSpacing(3)
                            .foregroundStyle(Color.ink45)
                    }
                }
                PrimaryButton("Try again") {
                    session.phase = .idle
                    showCapture = true
                }
                .padding(.top, 18)
                Button {
                    session.phase = .idle
                } label: {
                    MicroLabel("Not now", color: .ink45)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 24)
        }
    }

    private func unavailableAnalysis(onBack: (() -> Void)?) -> some View {
        ZStack {
            Color.bone.grain().ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                FloatCard(padding: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        MicroLabel("Swing unavailable", color: .brickText)
                        Text("This swing could not be opened.")
                            .font(Type.display(24))
                            .foregroundStyle(Color.ink)
                        Text("Its video or analysis file is missing or unreadable. Record or import another swing to continue.")
                            .font(Type.ui(13))
                            .lineSpacing(3)
                            .foregroundStyle(Color.ink70)
                    }
                }
                if let onBack { PrimaryButton("Back to swings", action: onBack) }
            }
            .padding(24)
        }
    }
}
