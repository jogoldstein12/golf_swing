import SwiftUI
import SwingKit

struct PendingSwingSource: Identifiable {
    let id = UUID()
    let url: URL
    let suggestedView: CaptureView
}

struct SwingSetupScreen: View {
    private static let maximumTrimDuration = 15.0
    private static let clubs = [
        "Driver", "3 Wood", "5 Wood", "Hybrid", "4 Iron", "5 Iron", "6 Iron",
        "7 Iron", "8 Iron", "9 Iron", "Pitching Wedge", "Gap Wedge", "Sand Wedge",
        "Lob Wedge"
    ]

    let source: PendingSwingSource
    let onCancel: () -> Void
    let onAnalyze: (SwingSetupSelection) -> Void

    @State private var metadata: VideoPreflightMetadata?
    @State private var errorMessage: String?
    @State private var trimStart = 0.0
    @State private var trimEnd = 0.0
    @State private var view: CaptureView
    @State private var club: String
    @State private var handedness: HandednessPreference
    @State private var isLoading = true
    @AppStorage("swingSetup.lastClub") private var storedClub = "7 Iron"
    @AppStorage("swingSetup.handedness") private var storedHandedness = HandednessPreference.automatic.rawValue

    init(source: PendingSwingSource,
         onCancel: @escaping () -> Void,
         onAnalyze: @escaping (SwingSetupSelection) -> Void) {
        self.source = source
        self.onCancel = onCancel
        self.onAnalyze = onAnalyze
        _view = State(initialValue: source.suggestedView)
        let defaults = UserDefaults.standard
        _club = State(initialValue: defaults.string(forKey: "swingSetup.lastClub") ?? "7 Iron")
        _handedness = State(initialValue: HandednessPreference(
            rawValue: defaults.string(forKey: "swingSetup.handedness") ?? ""
        ) ?? .automatic)
    }

    var body: some View {
        ZStack {
            Color.bone.grain().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if isLoading {
                        loadingState
                    } else if let errorMessage {
                        errorState(errorMessage)
                    } else if let metadata {
                        setupForm(metadata)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 36)
            }
        }
        .interactiveDismissDisabled()
        .task { await preflight() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                MicroLabel("Set up analysis")
                Text("One swing, clearly framed.")
                    .font(Type.display(30))
                    .foregroundStyle(Color.ink)
            }
            Spacer()
            Button("Cancel", action: onCancel)
                .font(Type.ui(13, .medium))
                .foregroundStyle(Color.ink70)
        }
    }

    private var loadingState: some View {
        FloatCard(padding: 24) {
            HStack(spacing: 12) {
                ProgressView()
                Text("Preparing your local video…")
                    .font(Type.ui(14))
                    .foregroundStyle(Color.ink70)
            }
        }
    }

    private func errorState(_ message: String) -> some View {
        FloatCard(padding: 24) {
            VStack(alignment: .leading, spacing: 10) {
                MicroLabel("Video unavailable", color: .brickText)
                Text(message)
                    .font(Type.ui(14))
                    .foregroundStyle(Color.ink70)
                Button("Try again") { Task { await preflight() } }
                    .font(Type.ui(13, .medium))
                    .foregroundStyle(Color.brickText)
            }
        }
    }

    private func setupForm(_ metadata: VideoPreflightMetadata) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            LoopingPlayerView(url: source.url, playbackRange: trimStart...trimEnd)
                .frame(height: 250)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .accessibilityLabel("Selected swing video preview")

            FloatCard(padding: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        MicroLabel("Trim one swing")
                        Spacer()
                        Text("\(time(trimStart))–\(time(trimEnd))")
                            .font(Type.ui(12, .medium))
                            .foregroundStyle(Color.ink70)
                    }
                    Text("Keep the selection under 15 seconds. The original video stays intact.")
                        .font(Type.ui(12.5))
                        .foregroundStyle(Color.ink70)
                    Slider(value: startBinding, in: 0...max(0.01, metadata.duration - 0.5))
                        .accessibilityLabel("Trim start")
                    Slider(value: endBinding, in: min(0.5, metadata.duration)...metadata.duration)
                        .accessibilityLabel("Trim end")
                    Text("\(metadata.displayWidth)×\(metadata.displayHeight) · \(Int(metadata.nominalFPS.rounded())) fps · \(metadata.codec.uppercased())\(metadata.isHDR ? " · HDR" : "")")
                        .font(Type.ui(11))
                        .foregroundStyle(Color.ink45)
                }
            }

            selectionPicker("Camera angle", selection: $view) {
                Text("Down the line").tag(CaptureView.downTheLine)
                Text("Face on").tag(CaptureView.faceOn)
            }
            selectionPicker("Club", selection: $club) {
                ForEach(Self.clubs, id: \.self) { Text($0).tag($0) }
            }
            selectionPicker("Golfer", selection: $handedness) {
                ForEach(HandednessPreference.allCases) { Text($0.label).tag($0) }
            }

            PrimaryButton("Analyze swing") {
                storedClub = club
                storedHandedness = handedness.rawValue
                onAnalyze(SwingSetupSelection(
                    videoURL: source.url,
                    metadata: metadata,
                    trimStart: trimStart,
                    trimEnd: trimEnd,
                    view: view,
                    club: club,
                    handedness: handedness
                ))
            }
            .disabled(trimEnd - trimStart < 0.5)
        }
    }

    private func selectionPicker<Selection: Hashable, Content: View>(
        _ title: String,
        selection: Binding<Selection>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        FloatCard(padding: 18) {
            HStack {
                MicroLabel(title)
                Spacer()
                Picker(title, selection: selection, content: content)
                    .labelsHidden()
                    .tint(Color.ink)
            }
        }
    }

    private var startBinding: Binding<Double> {
        Binding(
            get: { trimStart },
            set: { value in
                trimStart = min(value, trimEnd - 0.5)
                if trimEnd - trimStart > Self.maximumTrimDuration {
                    trimEnd = trimStart + Self.maximumTrimDuration
                }
            }
        )
    }

    private var endBinding: Binding<Double> {
        Binding(
            get: { trimEnd },
            set: { value in
                trimEnd = max(value, trimStart + 0.5)
                if trimEnd - trimStart > Self.maximumTrimDuration {
                    trimStart = trimEnd - Self.maximumTrimDuration
                }
            }
        )
    }

    @MainActor
    private func preflight() async {
        isLoading = true
        errorMessage = nil
        do {
            let value = try await VideoPreflightService().inspect(url: source.url)
            metadata = value
            trimStart = 0
            trimEnd = min(value.duration, Self.maximumTrimDuration)
            isLoading = false
        } catch is CancellationError {
            return
        } catch {
            metadata = nil
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func time(_ seconds: Double) -> String {
        String(format: "%.1fs", seconds)
    }
}
