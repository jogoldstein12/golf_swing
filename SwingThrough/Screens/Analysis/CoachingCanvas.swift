// WS-E / NP-2 — the coaching band below the hero card: goal #1's external-focus caption
// and the two next actions ("see the fix" seeks the scrubber to the fault checkpoint;
// "drill" opens its page). The actual lines now draw directly over the video's own
// pixels (PlaneOverlay, in the hero card above) so they read as measured, not
// illustrative; this band is honest by construction too — it only ever describes the
// primitives SwingOverlay handed the plan, never invents a caption for a withheld read.
import SwiftUI
import SwingKit

struct CoachingCanvas: View {
    let plan: OverlayPlan
    /// The drill this goal prescribes — shown on the "Drill" pill.
    var drillName: String? = nil
    /// Seek the scrubber to the fault checkpoint.
    let onSeeFix: () -> Void
    /// Open the drill's detail page.
    let onDrill: () -> Void
    /// "More lines" disclosure — shared with the video-space PlaneOverlay above so the
    /// two views always agree on what's drawn.
    @Binding var showAdvanced: Bool

    var body: some View {
        VStack(spacing: 0) {
            caption
            controls
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.paper)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .floatShadow()
    }

    // MARK: - Caption + controls

    private var caption: some View {
        HStack {
            Text(plan.caption)
                .font(Type.display(15))
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onSeeFix) {
                    HStack(spacing: 6) {
                        PlayGlyph().fill(Color.ink).frame(width: 7, height: 8)
                        Text("See the fix")
                            .font(Type.ui(12, .medium))
                            .foregroundStyle(Color.ink)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule().strokeBorder(Color.ink25, lineWidth: 1))
                    .contentShape(Capsule())
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityIdentifier("seeFix")

                if let drillName {
                    Button(action: onDrill) {
                        Text("Drill: \(drillName) →")
                            .font(Type.ui(11, .bold))
                            .foregroundStyle(Color.fairwayText)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().fill(Color.fairway.opacity(0.16)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityIdentifier("canvasDrill")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            if !plan.advancedOnly.isEmpty {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showAdvanced.toggle()
                    }
                } label: {
                    MicroLabel(showAdvanced ? "▾ fewer lines" : "▸ more lines", color: .ink45, size: 9)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(height: 18)
            }
        }
    }
}
