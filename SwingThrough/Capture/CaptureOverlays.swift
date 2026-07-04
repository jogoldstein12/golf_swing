// Everything drawn over (and directly under) the live preview: framing guides, the
// checklist chips, the armed indicator, the live skeleton, the countdown numerals, the
// manual record control, and the angle selector. All glyphs are hand-drawn Shapes —
// no SF Symbols, no emoji. Fairway appears only on the active/OK state.
import SwiftUI
import SwingKit
import simd

// MARK: - Framing guides

/// Hairline guides in the video's normalized space: subject zone, ground line, and a
/// down-the-line aim hint. Bone lines over a whisper of scrim; the zone flips to
/// fairway when armed — the single accent.
struct FramingGuides: View {
    let angle: CaptureView
    let armed: Bool

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let zone = zoneRect(in: size)
            let lineColor = armed
                ? Color.fairway.opacity(0.9)
                : Color.bone.opacity(0.75)

            // Subject zone
            let zonePath = Path(roundedRect: zone, cornerRadius: 22, style: .continuous)
            ctx.stroke(zonePath, with: .color(lineColor), lineWidth: 1)

            // Corner ticks — a touch of instrument
            let tick: CGFloat = 14
            for (cx, cy, dx, dy) in [
                (zone.minX, zone.minY, 1.0, 1.0), (zone.maxX, zone.minY, -1.0, 1.0),
                (zone.minX, zone.maxY, 1.0, -1.0), (zone.maxX, zone.maxY, -1.0, -1.0),
            ] {
                var p = Path()
                p.move(to: CGPoint(x: cx + CGFloat(dx) * 22, y: cy))
                p.addLine(to: CGPoint(x: cx + CGFloat(dx) * (22 + tick), y: cy))
                p.move(to: CGPoint(x: cx, y: cy + CGFloat(dy) * 22))
                p.addLine(to: CGPoint(x: cx, y: cy + CGFloat(dy) * (22 + tick)))
                ctx.stroke(p, with: .color(lineColor), lineWidth: 2)
            }

            // Ground line
            var ground = Path()
            ground.move(to: CGPoint(x: w * 0.06, y: h * groundY))
            ground.addLine(to: CGPoint(x: w * 0.94, y: h * groundY))
            ctx.stroke(ground, with: .color(Color.bone.opacity(0.55)),
                       style: StrokeStyle(lineWidth: 1, dash: [1, 5]))

            // DTL aim hint: the target line receding from the ball position.
            if angle == .downTheLine {
                var aim = Path()
                aim.move(to: CGPoint(x: w * 0.60, y: h * groundY))
                aim.addLine(to: CGPoint(x: w * 0.50, y: h * 0.14))
                ctx.stroke(aim, with: .color(Color.bone.opacity(0.5)),
                           style: StrokeStyle(lineWidth: 1, dash: [5, 6]))
            }
        }
        .allowsHitTesting(false)
    }

    private var groundY: CGFloat { 0.86 }

    private func zoneRect(in size: CGSize) -> CGRect {
        let x0: CGFloat = angle == .downTheLine ? 0.15 : 0.12
        let x1: CGFloat = angle == .downTheLine ? 0.85 : 0.88
        return CGRect(x: size.width * x0, y: size.height * 0.10,
                      width: size.width * (x1 - x0),
                      height: size.height * (groundY - 0.10))
    }
}

/// Micro-labels pinned to the guides (kept outside Canvas for real type).
struct GuideLabels: View {
    let angle: CaptureView

    var body: some View {
        GeometryReader { geo in
            MicroLabel("Ground", color: .bone.opacity(0.55), size: 8)
                .position(x: geo.size.width * 0.135, y: geo.size.height * 0.86 - 9)
            if angle == .downTheLine {
                MicroLabel("Target", color: .bone.opacity(0.55), size: 8)
                    .position(x: geo.size.width * 0.50, y: geo.size.height * 0.115)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Live skeleton

struct SkeletonOverlay: View {
    let joints: [Joint: SIMD2<Double>]

    var body: some View {
        Canvas { ctx, size in
            var lines = Path()
            for (a, b) in Bones.all {
                guard let pa = joints[a], let pb = joints[b] else { continue }
                lines.move(to: CGPoint(x: pa.x * size.width, y: pa.y * size.height))
                lines.addLine(to: CGPoint(x: pb.x * size.width, y: pb.y * size.height))
            }
            ctx.stroke(lines, with: .color(Color.ink.opacity(0.4)), lineWidth: 1.5)
            for (_, p) in joints {
                let r: CGFloat = 2.6
                let dot = CGRect(x: p.x * size.width - r, y: p.y * size.height - r,
                                 width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: dot), with: .color(Color.ink.opacity(0.65)))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Status indicator (armed dot breathes)

struct CaptureStatusBadge: View {
    let phase: SwingDetector.Phase
    @State private var breathe = false

    private var label: String {
        switch phase {
        case .idle(let hold): hold > 0 ? "Hold still" : "Setting up"
        case .ready: "Armed"
        case .capturing: "Capturing"
        case .settling: "Hold finish"
        case .captured: "Captured"
        }
    }

    private var dotColor: Color {
        switch phase {
        case .idle: .ink25
        case .ready: .fairwayDeep
        case .capturing, .settling: .brick
        case .captured: .fairwayDeep
        }
    }

    private var isBreathing: Bool {
        if case .ready = phase { return true }
        return false
    }

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                // Stillness-hold progress ring, only while the gate fills.
                if case .idle(let hold) = phase, hold > 0 {
                    Circle()
                        .trim(from: 0, to: hold)
                        .stroke(Color.bone.opacity(0.9),
                                style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 13, height: 13)
                }
                Circle()
                    .fill(dotColor)
                    .frame(width: 6.5, height: 6.5)
                    .scaleEffect(isBreathing && breathe ? 1.45 : 1)
                    .opacity(isBreathing && breathe ? 0.55 : 1)
            }
            .frame(width: 14, height: 14)
            MicroLabel(label, color: .ink70)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.bone.opacity(0.85)))
        .onAppear { startBreathing() }
        .onChange(of: isBreathing) { startBreathing() }
    }

    private func startBreathing() {
        guard isBreathing else { breathe = false; return }
        breathe = false
        withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
            breathe = true
        }
    }
}

// MARK: - Checklist chips

struct ChecklistChips: View {
    let checklist: SetupChecklist

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(SetupChecklist.Item.allCases.enumerated()), id: \.offset) { _, item in
                chip(item, on: checklist.satisfied(item))
            }
        }
    }

    private func chip(_ item: SetupChecklist.Item, on: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(on ? Color.fairwayDeep : Color.ink25)
                .frame(width: 5, height: 5)
            Text(item.label.uppercased())
                .font(Type.ui(10, .bold))
                .tracking(1.1)
                .foregroundStyle(on ? Color.fairwayText : Color.ink45)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(Color.paper)
                .overlay(Capsule().strokeBorder(
                    on ? Color.fairwayDeep.opacity(0.35) : Color.ink08, lineWidth: 1))
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: on)
    }
}

// MARK: - Countdown numerals

struct CountdownOverlay: View {
    let count: Int

    var body: some View {
        ZStack {
            Color.ink.opacity(0.28)
            Text("\(count)")
                .font(Type.display(148))
                .foregroundStyle(Color.bone)
                .shadow(color: .ink.opacity(0.35), radius: 24, y: 8)
                .id(count)
                .transition(.asymmetric(
                    insertion: .scale(scale: 1.35).combined(with: .opacity),
                    removal: .scale(scale: 0.9).combined(with: .opacity)))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Manual record control

struct RecordButton: View {
    let counting: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(Color.bone.opacity(0.9), lineWidth: 2)
                    .frame(width: 56, height: 56)
                if counting {
                    CrossGlyph()
                        .stroke(Color.bone, style: StrokeStyle(
                            lineWidth: 2, lineCap: .round))
                        .frame(width: 15, height: 15)
                } else {
                    Circle()
                        .fill(Color.bone.opacity(0.92))
                        .frame(width: 40, height: 40)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
    }
}

// MARK: - Angle selector (matches the reference pane toggle)

struct AngleSelector: View {
    let angle: CaptureView
    let onSelect: (CaptureView) -> Void
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            option("DTL", .downTheLine)
            option("Face on", .faceOn)
        }
        .padding(3)
        .background(Capsule().fill(Color.bone.opacity(0.85)))
    }

    private func option(_ label: String, _ value: CaptureView) -> some View {
        Button {
            onSelect(value)
        } label: {
            Text(label.uppercased())
                .font(Type.ui(10, .bold))
                .tracking(1.2)
                .foregroundStyle(angle == value ? Color.bone : Color.ink45)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background {
                    if angle == value {
                        Capsule().fill(Color.ink)
                            .matchedGeometryEffect(id: "pill", in: ns)
                    }
                }
        }
        .buttonStyle(PressScaleStyle())
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: angle)
    }
}

// MARK: - Hand-drawn glyphs (Check/Cross come from DesignSystem/Glyphs.swift)

/// Camera-absent mark for the designed empty states: a lens ring with a quiet slash.
struct NoCameraGlyph: View {
    var body: some View {
        ZStack {
            Circle().strokeBorder(Color.ink25, lineWidth: 1)
            Circle().strokeBorder(Color.ink25, lineWidth: 1)
                .frame(width: 26, height: 26)
            Circle().fill(Color.ink45).frame(width: 7, height: 7)
            SlashGlyph()
                .stroke(Color.ink, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        }
        .frame(width: 64, height: 64)
    }
}

struct SlashGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + rect.width * 0.18,
                           y: rect.minY + rect.height * 0.82))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.82,
                              y: rect.minY + rect.height * 0.18))
        return p
    }
}
