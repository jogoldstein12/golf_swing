// Home: the swing gallery. Editorial layout — wordmark, score-trend hero, swing list,
// one primary action. Each swing opens the full analysis.
import SwiftData
import SwiftUI
import SwingKit
import PhotosUI
import CoreTransferable
import UniformTypeIdentifiers

private struct ImportedSwingVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            // The picker-owned URL is only guaranteed to live for this closure.
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("import-\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return ImportedSwingVideo(url: copy)
        }
    }
}

struct HomeScreen: View {
    @Query(sort: \SwingRecord.date, order: .reverse) private var swings: [SwingRecord]
    @Query(sort: \AnalysisJobRecord.updatedAt, order: .reverse) private var analysisJobs: [AnalysisJobRecord]
    @Query(sort: \FocusRecord.createdAt, order: .reverse) private var focuses: [FocusRecord]
    @Environment(\.modelContext) private var context
    var onRecord: () -> Void = {}
    var onImport: (URL) -> Void = { _ in }
    var onOpen: (SwingRecord) -> Void = { _ in }
    var onDrills: () -> Void = {}
    var onRetryDraft: (UUID) -> Void = { _ in }
    var onDiscardDraft: (UUID) -> Void = { _ in }

    var body: some View {
        ZStack {
            Color.bone.grain().ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    heading.padding(.top, 36)

                    if let focus = activeFocus {
                        activeFocusCard(focus).padding(.top, 20)
                    }

                    if !analysisJobs.isEmpty {
                        draftList.padding(.top, 22)
                    }

                    if swings.isEmpty {
                        emptyState.padding(.top, 24)
                    } else {
                        if swings.count >= 2 {
                            trendCard.padding(.top, 20)
                        }
                        swingList.padding(.top, swings.count >= 2 ? 28 : 16)
                    }

                    drillsRow.padding(.top, 26)

                    PrimaryButton("Record a swing", action: onRecord)
                        .padding(.top, 26)

                    importButton.padding(.top, 12)
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 40)
            }
        }
        .onAppear(perform: seedSampleIfEmpty)
        .alert("Couldn't import that video", isPresented: $showImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Choose a video that is stored on this iPhone or available to download from iCloud.")
        }
        .confirmationDialog(
            "Delete this swing?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete video and report", role: .destructive) { deletePendingSwing() }
            Button("Cancel", role: .cancel) { pendingDeleteID = nil }
        } message: {
            Text("This permanently removes the saved analysis from this iPhone.")
        }
    }

    @State private var showSettings = false
    @State private var selectedVideo: PhotosPickerItem?
    @State private var importingVideo = false
    @State private var showImportError = false
    @State private var sampleUnavailable = false
    @State private var pendingDeleteID: UUID?
    @State private var showDeleteConfirmation = false

    private static let editableClubs = [
        "Driver", "3 Wood", "5 Wood", "Hybrid", "5 Iron", "6 Iron", "7 Iron",
        "8 Iron", "9 Iron", "Pitching Wedge", "Gap Wedge", "Sand Wedge", "Lob Wedge"
    ]

    private var scoredSwings: [SwingRecord] { swings.filter { $0.score >= 0 } }

    private var header: some View {
        HStack {
            Text("Swing Through")
                .font(Type.display(23))
                .foregroundStyle(Color.ink)
            Spacer()
            Button {
                showSettings = true
            } label: {
                Circle().fill(Color.ink).frame(width: 26, height: 26)
                    .contentShape(Circle())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityIdentifier("settings")
        }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
    }

    private var heading: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                MicroLabel("Your swings")
                headline
            }
            Spacer()
            if let latest = swings.first {
                MicroLabel(latest.date.formatted(.dateTime.day(.twoDigits)) + " · "
                           + latest.date.formatted(.dateTime.month(.twoDigits)))
                    .padding(.bottom, 4)
            }
        }
    }

    private var headline: some View {
        let latest = scoredSwings.first?.score
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let latest {
                Text("\(latest)")
                    .font(Type.display(56))
                    .foregroundStyle(Color.ink)
                Text(trendText)
                    .font(Type.displayItalic(20))
                    .foregroundStyle(Color.ink45)
            } else {
                Text("First swing")
                    .font(Type.display(34))
                    .foregroundStyle(Color.ink)
            }
        }
    }

    private var trendText: String {
        guard scoredSwings.count >= 2 else { return "your latest score" }
        let delta = scoredSwings[0].score - scoredSwings[1].score
        if delta > 0 { return "up \(delta) from last swing" }
        if delta < 0 { return "down \(-delta) from last swing" }
        return "level with last swing"
    }

    // MARK: - Active focus (WS-E practice loop)

    /// The one thing being worked on, if any — the most recent unresolved focus.
    private var activeFocus: FocusRecord? { focuses.first { !$0.isResolved } }

    private func activeFocusCard(_ focus: FocusRecord) -> some View {
        FloatCard(padding: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    MicroLabel("Working on", color: .fairwayText)
                    Spacer()
                    MicroLabel(focus.club, color: .ink25, size: 9)
                }
                Text(focus.goalTitle)
                    .font(Type.display(19))
                    .foregroundStyle(Color.ink)
                Text(focus.cue)
                    .font(Type.ui(13.5))
                    .lineSpacing(3.5)
                    .foregroundStyle(Color.ink70)
                Button(action: onRecord) {
                    HStack(spacing: 6) {
                        MicroLabel("Record to check", color: .ink, size: 9)
                        ChevronGlyph()
                            .stroke(Color.ink, style: .init(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                            .frame(width: 5, height: 9)
                    }
                    .padding(.top, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle())
            }
        }
        .accessibilityIdentifier("activeFocus")
    }

    // MARK: - Trend

    private var trendCard: some View {
        FloatCard(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    MicroLabel("Score trend")
                    Spacer()
                    MicroLabel("Last \(min(swings.count, 12))", color: .ink25)
                }
                TrendChart(scores: scoredSwings.prefix(12).reversed().map(\.score))
                    .frame(height: 88)
            }
        }
    }

    // MARK: - List

    private var draftList: some View {
        VStack(alignment: .leading, spacing: 0) {
            MicroLabel("Saved analyses")
                .padding(.bottom, 6)
            ForEach(Array(analysisJobs.enumerated()), id: \.element.id) { index, job in
                if index > 0 { Hairline() }
                AnalysisDraftRow(
                    job: job,
                    canRetry: SwingStore.videoExists(named: job.videoFileName),
                    onRetry: { onRetryDraft(job.id) },
                    onDiscard: { onDiscardDraft(job.id) }
                )
            }
        }
    }

    private var swingList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                MicroLabel("History")
                Spacer()
            }
            .padding(.bottom, 6)
            ForEach(Array(swings.enumerated()), id: \.element.id) { i, s in
                if i > 0 { Hairline() }
                Button { onOpen(s) } label: { SwingRow(record: s) }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityIdentifier("swingRow")
                    .contextMenu {
                        Menu("Correct club") {
                            ForEach(Self.editableClubs, id: \.self) { club in
                                Button(club) { update(s, club: club) }
                            }
                        }
                        Menu("Correct camera angle") {
                            Button("Down the line") { update(s, view: .downTheLine) }
                            Button("Face on") { update(s, view: .faceOn) }
                        }
                        Button("Delete swing", role: .destructive) {
                            pendingDeleteID = s.id
                            showDeleteConfirmation = true
                        }
                    }
            }
        }
    }

    private var drillsRow: some View {
        Button(action: onDrills) {
            VStack(spacing: 0) {
                Hairline()
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Drill library")
                            .font(Type.display(19))
                            .foregroundStyle(Color.ink)
                        MicroLabel("Keyed to your faults", color: .ink45, size: 9)
                    }
                    Spacer()
                    ChevronGlyph()
                        .stroke(Color.ink25, style: .init(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        .frame(width: 6, height: 11)
                }
                .padding(.vertical, 16)
                Hairline()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityIdentifier("drills")
    }

    private var emptyState: some View {
        FloatCard(padding: 28) {
            VStack(alignment: .leading, spacing: 10) {
                MicroLabel("No swings yet")
                Text("Your first swing lives here.")
                    .font(Type.display(24))
                    .foregroundStyle(Color.ink)
                Text("Record one down-the-line and Swing Through will measure the plane, sequence, and tempo — then coach you through what it finds.")
                    .font(Type.ui(13.5))
                    .lineSpacing(3.5)
                    .foregroundStyle(Color.ink70)
                if sampleUnavailable {
                    Text("The bundled sample could not be loaded. Recording and video import are still available.")
                        .font(Type.ui(12))
                        .lineSpacing(3)
                        .foregroundStyle(Color.brickText)
                        .padding(.top, 4)
                }
            }
        }
    }

    private var importButton: some View {
        PhotosPicker(selection: $selectedVideo, matching: .videos) {
            HStack(spacing: 8) {
                if importingVideo { ProgressView().controlSize(.small) }
                MicroLabel(importingVideo ? "Importing video" : "Import a video", color: .ink70)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Capsule().stroke(Color.ink25, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .disabled(importingVideo)
        .onChange(of: selectedVideo) { _, item in
            guard let item else { return }
            importingVideo = true
            Task {
                do {
                    guard let video = try await item.loadTransferable(type: ImportedSwingVideo.self) else {
                        throw CocoaError(.fileReadUnknown)
                    }
                    importingVideo = false
                    selectedVideo = nil
                    onImport(video.url)
                } catch {
                    importingVideo = false
                    selectedVideo = nil
                    showImportError = true
                }
            }
        }
    }

    /// Ship with the sample swing in the gallery so the whole app is explorable
    /// before the first real capture. Clearly labeled; removable.
    private func seedSampleIfEmpty() {
        guard swings.isEmpty else { return }
        // Only auto-seed into a genuinely empty gallery (so a sample the user removed
        // while they have real swings stays removed). SampleSeed persists the record.
        sampleUnavailable = !SampleSeed.ensure(in: context)
    }

    private func update(_ record: SwingRecord, club: String? = nil,
                        view: CaptureView? = nil) {
        if let club { record.club = club }
        if let view { record.viewRaw = view.rawValue }
        if !record.isSample,
           var report = SwingStore.loadReport(named: record.reportFileName) {
            if let club { report.club = club }
            if let view { report.view = view }
            _ = try? SwingStore.saveReport(report)
        }
        try? context.save()
    }

    private func deletePendingSwing() {
        guard let id = pendingDeleteID,
              let record = swings.first(where: { $0.id == id }) else { return }
        if let video = record.videoFileName { try? SwingStore.removeVideo(named: video) }
        if !record.reportFileName.isEmpty {
            try? SwingStore.removeReport(named: record.reportFileName)
        }
        try? SwingStore.removeJobFiles(jobID: record.id)
        context.delete(record)
        try? context.save()
        pendingDeleteID = nil
    }
}

private struct AnalysisDraftRow: View {
    let job: AnalysisJobRecord
    let canRetry: Bool
    let onRetry: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onRetry) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.draft.statusLabel)
                        .font(Type.display(19))
                        .foregroundStyle(job.stage == .failed ? Color.brickText : Color.ink)
                    MicroLabel(
                        canRetry
                            ? "\(job.club) · tap to retry"
                            : "Video unavailable",
                        color: .ink45,
                        size: 9
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canRetry)
            .accessibilityIdentifier("analysisDraft")

            Button(action: onDiscard) {
                MicroLabel("Discard", color: .brickText, size: 8.5)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Discard saved analysis")
        }
        .padding(.vertical, 14)
    }
}

// MARK: - Trend chart (custom Canvas — thin editorial line, fairway on the latest)

struct TrendChart: View {
    let scores: [Int]

    var body: some View {
        Canvas { ctx, size in
            guard !scores.isEmpty else { return }
            let lo = Double(min(scores.min() ?? 0, 60))
            let hi = Double(max(scores.max() ?? 100, 90))
            let xStep = scores.count > 1 ? size.width / CGFloat(scores.count - 1) : 0
            func pt(_ i: Int) -> CGPoint {
                let t = (Double(scores[i]) - lo) / max(hi - lo, 1)
                let x = scores.count > 1 ? CGFloat(i) * xStep : size.width / 2
                return CGPoint(x: x, y: size.height * (1 - 0.15 - 0.7 * t))
            }

            // Hairline baselines
            for f: CGFloat in [0.15, 0.5, 0.85] {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: size.height * f))
                line.addLine(to: CGPoint(x: size.width, y: size.height * f))
                ctx.stroke(line, with: .color(.ink08), lineWidth: 1)
            }

            // The line
            if scores.count > 1 {
                var path = Path()
                path.move(to: pt(0))
                for i in 1..<scores.count { path.addLine(to: pt(i)) }
                ctx.stroke(path, with: .color(.ink45),
                           style: .init(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }

            // Dots — ink for history, fairway ring for the latest
            for i in scores.indices {
                let c = pt(i)
                let latest = i == scores.count - 1
                if latest {
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)),
                             with: .color(.fairwayDeep))
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 6.5, y: c.y - 6.5, width: 13, height: 13)),
                               with: .color(.fairwayDeep.opacity(0.35)), lineWidth: 1.5)
                } else {
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - 2.5, y: c.y - 2.5, width: 5, height: 5)),
                             with: .color(.ink25))
                }
            }
        }
    }
}

// MARK: - Row

struct SwingRow: View {
    let record: SwingRecord

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(dayText)
                        .font(Type.display(19))
                        .foregroundStyle(Color.ink)
                    if record.isSample {
                        MicroLabel("Sample", color: .ink25, size: 8.5)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().fill(Color.sand))
                    }
                }
                MicroLabel("\(record.club) · \(record.viewRaw == CaptureView.downTheLine.rawValue ? "DTL" : "Face-on")",
                           color: .ink45, size: 9)
            }
            Spacer()
            if record.score >= 0 {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(record.score)")
                        .font(Type.display(28))
                        .foregroundStyle(Color.ink)
                    Text("/100")
                        .font(Type.display(13))
                        .foregroundStyle(Color.ink25)
                }
            } else {
                MicroLabel("Limited data", color: .ink45, size: 9)
            }
            ChevronGlyph()
                .stroke(Color.ink25, style: .init(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                .frame(width: 6, height: 11)
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }

    private var dayText: String {
        if Calendar.current.isDateInToday(record.date) { return "Today" }
        if Calendar.current.isDateInYesterday(record.date) { return "Yesterday" }
        return record.date.formatted(.dateTime.weekday(.wide).day().month())
    }
}
