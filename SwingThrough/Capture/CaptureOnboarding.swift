// First-run capture walkthrough. Unlike the static SetupSheet, this one is LIVE: each
// setup requirement lights up as the camera actually sees it satisfied, so the very first
// thing a new user does is watch the four checks go green on themselves. It shows once
// (gated on the `capture.hasSeenOnboarding` flag), and is re-openable from Settings.
import SwiftUI
import SwingKit

struct CaptureOnboarding: View {
    @ObservedObject var controller: CaptureController
    @Environment(\.dismiss) private var dismiss

    /// Defaults key for the show-once gate. Owned here so the gating logic and its test
    /// share one source of truth.
    static let hasSeenDefaultsKey = "capture.hasSeenOnboarding"

    /// Pure gate: present the first-run walkthrough only when it has not yet been seen.
    static func shouldPresent(hasSeenOnboarding: Bool) -> Bool { !hasSeenOnboarding }

    private struct Row {
        let item: SetupChecklist.Item
        let title: String
        let detail: String
    }

    private let rows: [Row] = [
        Row(item: .upright,
            title: "Stand the phone upright",
            detail: "Prop it vertically at about hand height — a tripod, a bag, or a "
                + "wall. Keep it steady; a leaning phone skews every angle we measure."),
        Row(item: .body,
            title: "Fit your whole body in frame",
            detail: "Cap to spikes stays inside the guide through the finish. If the "
                + "swing leaves the frame, the swing can't be measured."),
        Row(item: .distance,
            title: "Get the distance right",
            detail: "About ten feet (3 m) back, feet on the ground line, filling the "
                + "zone — not so close you crop, not so far you shrink."),
        Row(item: .light,
            title: "Find even light",
            detail: "A plain background and flat, even light keep the joint tracking "
                + "honest. Avoid strong backlight behind you."),
    ]

    var body: some View {
        ZStack {
            Color.bone.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header

                Text(controller.angle == .downTheLine
                     ? "You're set up down the line — the camera looks along your target "
                       + "line, the view that reveals swing plane. Switch angles anytime "
                       + "with the selector."
                     : "You're set up face on — the camera faces your chest, the view "
                       + "that reveals turn, sway, and tempo. Switch angles anytime with "
                       + "the selector.")
                    .font(Type.displayItalic(17))
                    .foregroundStyle(Color.ink70)
                    .padding(.top, 14)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                        if i > 0 { Hairline() }
                        stepRow(row)
                    }
                }
                .padding(.top, 14)

                Spacer(minLength: 12)

                statusBanner

                PrimaryButton("Got it") { dismiss() }
                    .padding(.top, 14)
            }
            .padding(.horizontal, 24)
            .padding(.top, 26)
            .padding(.bottom, 20)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.bone)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            MicroLabel("Before your first swing")
            Text("Set up to be measured")
                .font(Type.display(32))
                .foregroundStyle(Color.ink)
        }
    }

    private func stepRow(_ row: Row) -> some View {
        let on = controller.checklist.satisfied(row.item)
        return HStack(alignment: .top, spacing: 16) {
            liveDot(on: on)
                .frame(width: 22, alignment: .center)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(row.title)
                        .font(Type.ui(14, .medium))
                        .foregroundStyle(Color.ink)
                    Text(on ? "Ready" : "Waiting")
                        .font(Type.ui(9, .bold))
                        .tracking(1.1)
                        .foregroundStyle(on ? Color.fairwayText : Color.ink45)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(on ? Color.fairwayDeep.opacity(0.14)
                                                       : Color.sand))
                }
                Text(row.detail)
                    .font(Type.ui(12.5))
                    .lineSpacing(3.5)
                    .foregroundStyle(Color.ink70)
            }
        }
        .padding(.vertical, 16)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: on)
    }

    private func liveDot(on: Bool) -> some View {
        Circle()
            .fill(on ? Color.fairwayDeep : Color.ink25)
            .frame(width: 9, height: 9)
            .overlay(
                Circle()
                    .stroke(on ? Color.fairwayDeep.opacity(0.25) : Color.clear, lineWidth: 4)
            )
    }

    @ViewBuilder private var statusBanner: some View {
        let ready = controller.checklist.allSatisfied
        HStack(spacing: 10) {
            Circle()
                .fill(ready ? Color.fairwayDeep : Color.ink25)
                .frame(width: 6, height: 6)
            Text(ready
                 ? "You're set. Hold your address to arm — the swing records on its own."
                 : "As each check turns green above, you're closer to a clean capture.")
                .font(Type.displayItalic(15))
                .foregroundStyle(ready ? Color.fairwayText : Color.ink45)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: Radius.inner, style: .continuous)
                .fill(ready ? Color.fairwayDeep.opacity(0.10) : Color.sand.opacity(0.6))
        )
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: ready)
    }
}

private struct CaptureOnboarding_Previews: PreviewProvider {
    static var previews: some View { CaptureOnboarding(controller: CaptureController()) }
}
