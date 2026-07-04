// Dev harness for the 3D avatar module. Reached via ST_SCREEN=avatar (see RootView).
// Loads the real fixture tracks directly (not the full SwingReport plumbing — this
// harness is about the avatar only) and drives AvatarView with a scrub slider,
// play/pause, and plane/path/ghost toggles, styled with the app's design tokens.
import SwiftUI
import SwingKit

struct AvatarPreviewScreen: View {
    @State private var frames: [PoseFrame] = []
    @State private var time: Double = 1.5
    @State private var isPlaying = false
    @State private var showPlane = true
    @State private var showPath = true
    @State private var showGhost = false
    // Dev-only: overrides the stage height so the compact ~176pt / ~400pt Analysis-
    // screen pane sizes (this harness is otherwise fixed at 440pt) can be exercised
    // for camera-fit verification. See `ST_HEIGHT` in `loadFixture()`.
    @State private var stageHeightOverride: CGFloat?

    // Hand-read from the same fixture annotation used elsewhere (App/DemoData.swift):
    // address, top, impact, finish. The ghost reuses the identical track a half-beat
    // quicker, purely to exercise the compare path in this harness.
    private let primaryCheckpoints: [Double] = [1.50, 3.20, 4.18, 6.40]
    private var ghostCheckpoints: [Double] { primaryCheckpoints.map { max($0 - 0.16, 0) } }

    private var trackEnd: Double { frames.last?.time ?? 7.44 }

    private var ghost: GhostTrack? {
        guard showGhost, !frames.isEmpty else { return nil }
        return GhostTrack(frames: frames, checkpoints: ghostCheckpoints, primaryCheckpoints: primaryCheckpoints)
    }

    var body: some View {
        ZStack {
            Color.bone.grain().ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                header
                heading.padding(.top, 30)
                stage.padding(.top, 16)
                controls.padding(.top, 18)
                toggles.padding(.top, 14)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 22)
        }
        .onAppear(perform: loadFixture)
        .onChange(of: time) { _, newValue in
            if isPlaying, newValue >= trackEnd - 0.01 { isPlaying = false }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Swing Through")
                .font(Type.display(23))
                .foregroundStyle(Color.ink)
            Spacer()
            MicroLabel("Avatar module", color: .ink70)
        }
    }

    private var heading: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                MicroLabel("3D Avatar")
                Text("Down the line")
                    .font(Type.display(34))
                    .foregroundStyle(Color.ink)
            }
            Spacer()
            MicroLabel(frames.isEmpty ? "loading" : "\(frames.count) frames", color: .ink25)
        }
    }

    // MARK: - Stage

    private var stage: some View {
        AvatarView(frames: frames, time: $time, isPlaying: isPlaying, ghost: ghost,
                   planeAngle: nil, showPlane: showPlane, showPath: showPath, orbitEnabled: true)
            .frame(height: stageHeightOverride ?? 440)
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.paper))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.ink08, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 12) {
            scrubber
            HStack {
                playButton
                Spacer()
                Text(timecode(time))
                    .font(Type.ui(12, .medium))
                    .foregroundStyle(Color.ink70)
                    .monospacedDigit()
            }
        }
    }

    private var scrubber: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            let frac = trackEnd > 0 ? min(max(time / trackEnd, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.ink08).frame(height: 3)
                Capsule().fill(Color.fairwayDeep).frame(width: frac * w, height: 3)
                Circle().fill(Color.ink).frame(width: 14, height: 14)
                    .offset(x: frac * w - 7)
            }
            .frame(height: 14)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { v in
                    isPlaying = false
                    time = min(max(v.location.x / w, 0), 1) * trackEnd
                }
            )
        }
        .frame(height: 14)
    }

    private var playButton: some View {
        Button {
            if time >= trackEnd - 0.02 { time = frames.first?.time ?? 0 }
            isPlaying.toggle()
        } label: {
            ZStack {
                Circle().fill(Color.ink).frame(width: 34, height: 34)
                if isPlaying {
                    PauseGlyph().fill(Color.bone).frame(width: 10, height: 11)
                } else {
                    PlayGlyph().fill(Color.bone).frame(width: 10, height: 11).offset(x: 1)
                }
            }
        }
        .buttonStyle(PressScaleStyle())
    }

    // MARK: - Toggles

    private var toggles: some View {
        HStack(spacing: 8) {
            toggleChip("Plane", isOn: $showPlane)
            toggleChip("Path", isOn: $showPath)
            toggleChip("Ghost", isOn: $showGhost)
        }
    }

    private func toggleChip(_ title: String, isOn: Binding<Bool>) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { isOn.wrappedValue.toggle() }
        } label: {
            Text(title.uppercased())
                .font(Type.ui(10, .bold))
                .tracking(1.1)
                .foregroundStyle(isOn.wrappedValue ? Color.bone : Color.ink45)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(Capsule().fill(isOn.wrappedValue ? Color.ink : Color.sand))
        }
        .buttonStyle(PressScaleStyle())
    }

    // MARK: - Data

    private func timecode(_ t: Double) -> String {
        let s = max(Int(t), 0)
        let f = Int((t - Double(s)) * 25)
        return String(format: "00:%02d:%02d", s, f)
    }

    private func loadFixture() {
        guard frames.isEmpty,
              let url = Bundle.main.url(forResource: "sample_dtl_tracks", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([PoseFrame].self, from: data)
        else { return }
        frames = decoded
        time = 1.5

        // Dev hooks for frame-accurate verification screenshots, mirroring
        // AnalysisModel's ST_POS convention — never user-facing.
        let env = ProcessInfo.processInfo.environment
        if let t = env["ST_TIME"].flatMap(Double.init) { time = t }
        if let v = env["ST_PLANE"] { showPlane = (v as NSString).boolValue }
        if let v = env["ST_PATH"] { showPath = (v as NSString).boolValue }
        if let v = env["ST_GHOST"] { showGhost = (v as NSString).boolValue }
        if let h = env["ST_HEIGHT"].flatMap(Double.init) { stageHeightOverride = CGFloat(h) }
        if env["ST_AUTOPLAY"] == "1" { isPlaying = true }
    }
}
