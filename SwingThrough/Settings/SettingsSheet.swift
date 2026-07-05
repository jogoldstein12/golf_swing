// Settings: the coaching connection. Editorial, minimal — one decision on this sheet.
import SwiftData
import SwiftUI

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var swings: [SwingRecord]
    @Query private var jobs: [AnalysisJobRecord]
    @State private var keyInput = ""
    @State private var hasStoredKey = APIKeyStore.hasKey
    @State private var diagnostics = DiagnosticsStore.shared
    @State private var confirmDeleteAll = false

    var body: some View {
        ZStack {
            Color.bone.grain().ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    MicroLabel("Settings")
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        CrossGlyph().stroke(Color.ink45, style: .init(lineWidth: 1.6, lineCap: .round))
                            .frame(width: 11, height: 11)
                            .frame(width: 34, height: 34)
                            .background(Circle().strokeBorder(Color.ink08, lineWidth: 1))
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressScaleStyle())
                }

                Text("Coaching")
                    .font(Type.display(30))
                    .foregroundStyle(Color.ink)
                    .padding(.top, 26)

                Text("Swing Through measures your swing entirely on this phone. For coaching notes written by Claude, add an Anthropic API key — only the computed numbers are sent, never your video.")
                    .font(Type.ui(13.5))
                    .lineSpacing(3.5)
                    .foregroundStyle(Color.ink70)
                    .padding(.top, 10)

                FloatCard(padding: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(hasStoredKey ? Color.fairwayDeep : Color.ink25)
                                .frame(width: 6, height: 6)
                            MicroLabel(hasStoredKey ? "Claude coaching active" : "Offline coaching",
                                       color: hasStoredKey ? .fairwayText : .ink45)
                            Spacer()
                            if hasStoredKey {
                                Button {
                                    APIKeyStore.delete()
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                        hasStoredKey = false
                                    }
                                } label: {
                                    MicroLabel("Remove", color: .brickText)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if !hasStoredKey {
                            SecureField("sk-ant-…", text: $keyInput)
                                .font(Type.ui(14))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.sand.opacity(0.6))
                                )
                            Button {
                                APIKeyStore.save(keyInput.trimmingCharacters(in: .whitespacesAndNewlines))
                                keyInput = ""
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    hasStoredKey = APIKeyStore.hasKey
                                }
                            } label: {
                                Text("Connect")
                                    .font(Type.ui(14, .medium))
                                    .foregroundStyle(keyInput.isEmpty ? Color.ink25 : Color.bone)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(Capsule().fill(keyInput.isEmpty ? Color.sand : Color.ink))
                            }
                            .buttonStyle(PressScaleStyle())
                            .disabled(keyInput.isEmpty)
                        } else {
                            Text("Coaching notes are grounded in your measured swing — plane, sequence, tempo — and prioritized by what to fix first.")
                                .font(Type.ui(12.5))
                                .lineSpacing(3)
                                .foregroundStyle(Color.ink45)
                        }
                    }
                }
                .padding(.top, 22)

                Text("Without a key, the built-in coach applies the same swing model with the same priorities — it just writes a little more plainly.")
                    .font(Type.displayItalic(15))
                    .foregroundStyle(Color.ink45)
                    .padding(.top, 18)

#if DEBUG
                if let exportURL = diagnostics.latestExportURL {
                    ShareLink(item: exportURL) {
                        HStack {
                            MicroLabel("Export latest diagnostics", color: .ink70)
                            Spacer()
                            if let latest = diagnostics.latest {
                                Text(latest.jobID.uuidString.prefix(8))
                                    .font(Type.ui(11))
                                    .foregroundStyle(Color.ink25)
                            }
                        }
                        .padding(.top, 24)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Export latest analysis diagnostics")
                }
#endif

                Button(role: .destructive) {
                    confirmDeleteAll = true
                } label: {
                    HStack {
                        MicroLabel("Delete all local swing data", color: .brickText)
                        Spacer()
                    }
                    .padding(.top, 24)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(swings.isEmpty && jobs.isEmpty)

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(Radius.card)
        .confirmationDialog(
            "Delete all swing data?",
            isPresented: $confirmDeleteAll,
            titleVisibility: .visible
        ) {
            Button("Delete videos and reports", role: .destructive, action: deleteAllData)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes saved videos, reports, and unfinished analyses from this iPhone.")
        }
    }

    private func deleteAllData() {
        for record in swings {
            if let video = record.videoFileName { try? SwingStore.removeVideo(named: video) }
            if !record.reportFileName.isEmpty {
                try? SwingStore.removeReport(named: record.reportFileName)
            }
            try? SwingStore.removeJobFiles(jobID: record.id)
            modelContext.delete(record)
        }
        for job in jobs {
            try? SwingStore.removeJobFiles(jobID: job.id)
            modelContext.delete(job)
        }
        try? modelContext.save()
    }
}
