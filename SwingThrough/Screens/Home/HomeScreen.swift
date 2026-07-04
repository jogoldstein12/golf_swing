// Home: the swing gallery. Editorial layout — wordmark, score-trend hero, swing list,
// one primary action. Each swing opens the full analysis.
import SwiftData
import SwiftUI
import SwingKit

struct HomeScreen: View {
    @Query(sort: \SwingRecord.date, order: .reverse) private var swings: [SwingRecord]
    @Environment(\.modelContext) private var context
    var onRecord: () -> Void = {}
    var onOpen: (SwingRecord) -> Void = { _ in }

    var body: some View {
        ZStack {
            Color.bone.grain().ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    heading.padding(.top, 36)

                    if swings.isEmpty {
                        emptyState.padding(.top, 24)
                    } else {
                        if swings.count >= 2 {
                            trendCard.padding(.top, 20)
                        }
                        swingList.padding(.top, swings.count >= 2 ? 28 : 16)
                    }

                    PrimaryButton("Record a swing", action: onRecord)
                        .padding(.top, 32)
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 40)
            }
        }
        .onAppear(perform: seedSampleIfEmpty)
    }

    @State private var showSettings = false

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
        let latest = swings.first?.score
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
        guard swings.count >= 2 else { return "your latest score" }
        let delta = swings[0].score - swings[1].score
        if delta > 0 { return "up \(delta) from last swing" }
        if delta < 0 { return "down \(-delta) from last swing" }
        return "level with last swing"
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
                TrendChart(scores: swings.prefix(12).reversed().map(\.score))
                    .frame(height: 88)
            }
        }
    }

    // MARK: - List

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
            }
        }
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
            }
        }
    }

    /// Ship with the sample swing in the gallery so the whole app is explorable
    /// before the first real capture. Clearly labeled; removable.
    private func seedSampleIfEmpty() {
        guard swings.isEmpty else { return }
        let demo = DemoData.load().report
        let record = SwingRecord(
            id: demo.id, date: demo.date, club: demo.club, score: demo.score.total,
            viewRaw: demo.view.rawValue, reportFileName: "", videoFileName: nil,
            isSample: true
        )
        context.insert(record)
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
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(record.score)")
                    .font(Type.display(28))
                    .foregroundStyle(Color.ink)
                Text("/100")
                    .font(Type.display(13))
                    .foregroundStyle(Color.ink25)
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
