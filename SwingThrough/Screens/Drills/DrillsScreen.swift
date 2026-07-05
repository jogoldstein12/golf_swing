// The drill library, keyed to the user's swing. Drills prescribed by the latest
// coaching plan lead under "For your swing"; the full catalog follows. Editorial
// cards — name in serif, the fault it fixes as a micro-label, method in UI type.
import SwiftData
import SwiftUI
import SwingKit

struct DrillsScreen: View {
    @Query(sort: \SwingRecord.date, order: .reverse) private var swings: [SwingRecord]
    var onBack: (() -> Void)? = nil

    private struct Entry: Identifiable {
        var id: String { name }
        let name: String
        let detail: String
        let fixes: String
        let prescribed: Bool
    }

    private var catalog: [(Drill, String)] {
        [
            (Drills.pump, "Over the top · steep plane"),
            (Drills.stepChange, "Sequence · arms firing early"),
            (Drills.chair, "Early extension · posture"),
            (Drills.towelUnderArm, "Sway · disconnection"),
            (Drills.splitHandTakeaway, "Takeaway shape"),
            (Drills.feetTogether, "Coil · turning as a unit"),
            (Drills.pauseAtTop, "Tempo · rushed transition"),
            (Drills.headcoverOutsideBall, "Under plane · in-to-out path"),
            (Drills.mirrorCheckpoints, "Positions · checkpoint feel"),
        ]
    }

    /// Drill names prescribed by the most recent coaching plan.
    private var prescribed: [String: String] {
        guard let latest = swings.first else { return [:] }
        let report = latest.isSample
            ? DemoData.load()?.report
            : SwingStore.loadReport(named: latest.reportFileName)
        guard let goals = report?.coaching?.goals else { return [:] }
        return Dictionary(goals.map { ($0.drill, $0.title) }, uniquingKeysWith: { a, _ in a })
    }

    private var entries: [Entry] {
        let rx = prescribed
        return catalog.map { drill, fixes in
            Entry(name: drill.name, detail: drill.detail, fixes: fixes,
                  prescribed: rx.keys.contains { $0.lowercased().hasPrefix(drill.name.lowercased().replacingOccurrences(of: " drill", with: "")) || $0 == drill.name })
        }
        .sorted { a, b in a.prescribed && !b.prescribed }
    }

    var body: some View {
        ZStack {
            Color.bone.grain().ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    VStack(alignment: .leading, spacing: 8) {
                        MicroLabel("Drill library")
                        Text("Practice with intent.")
                            .font(Type.display(34))
                            .foregroundStyle(Color.ink)
                    }
                    .padding(.top, 36)

                    let list = entries
                    let forYou = list.filter(\.prescribed)
                    if !forYou.isEmpty {
                        MicroLabel("For your swing", color: .fairwayText)
                            .padding(.top, 28)
                        ForEach(forYou) { drillCard($0).padding(.top, 14) }
                    }

                    MicroLabel("The catalog", color: .ink25)
                        .padding(.top, 30)
                    ForEach(list.filter { !$0.prescribed }) { drillCard($0).padding(.top, 14) }
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 40)
            }
        }
    }

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
                        MicroLabel("Home", color: .ink70)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle())
            }
            Spacer()
        }
    }

    private func drillCard(_ e: Entry) -> some View {
        FloatCard(padding: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    MicroLabel(e.fixes, color: e.prescribed ? .fairwayText : .ink45, size: 9)
                    Spacer()
                    if e.prescribed {
                        Circle().fill(Color.fairwayDeep).frame(width: 6, height: 6)
                    }
                }
                Text(e.name)
                    .font(Type.display(21))
                    .foregroundStyle(Color.ink)
                Text(e.detail)
                    .font(Type.ui(13))
                    .lineSpacing(3.5)
                    .foregroundStyle(Color.ink70)
            }
        }
    }
}
