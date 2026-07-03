// Swing Through design tokens — the exact palette from the reference prototype.
// Canvas is warm bone, ink is warm near-black, and the fairway accent is rationed:
// live/active measurement and the primary action only. Faults are brick, off-plane amber.
import SwiftUI

public extension Color {
    // Canvas system
    static let bone = Color(red: 0xF5 / 255, green: 0xF3 / 255, blue: 0xEE / 255)
    static let paper = Color(red: 0xFC / 255, green: 0xFB / 255, blue: 0xF8 / 255)
    static let sand = Color(red: 0xEB / 255, green: 0xE7 / 255, blue: 0xDE / 255)

    // Ink system (warm near-black, stepped by opacity)
    static let ink = Color(red: 0x19 / 255, green: 0x17 / 255, blue: 0x12 / 255)
    static let ink70 = Color.ink.opacity(0.70)
    static let ink45 = Color.ink.opacity(0.45)
    static let ink25 = Color.ink.opacity(0.25)
    static let ink08 = Color.ink.opacity(0.08)

    // Signature accent — <5% of any screen
    static let fairway = Color(red: 0xB4 / 255, green: 0xE0 / 255, blue: 0x19 / 255)
    static let fairwayDeep = Color(red: 0x8F / 255, green: 0xB8 / 255, blue: 0x0F / 255)
    /// Legible fairway for small text on light ground.
    static let fairwayText = Color(red: 0x5F / 255, green: 0x7A / 255, blue: 0x08 / 255)

    // Semantic
    static let brick = Color(red: 0xCE / 255, green: 0x4A / 255, blue: 0x2C / 255)
    static let brickText = Color(red: 0xA5 / 255, green: 0x3A / 255, blue: 0x22 / 255)
    static let amber = Color(red: 0xDB / 255, green: 0x85 / 255, blue: 0x1F / 255)
    static let pine = Color(red: 0x1F / 255, green: 0x3D / 255, blue: 0x2F / 255)
}

public enum Radius {
    public static let card: CGFloat = 26
    public static let inner: CGFloat = 16
}

public extension View {
    /// The "light glass" float: soft, diffused ambient shadow under a paper card.
    func floatShadow() -> some View {
        shadow(color: .ink.opacity(0.04), radius: 1, y: 1)
            .shadow(color: .ink.opacity(0.10), radius: 16, y: 10)
    }

    func floatShadowLarge() -> some View {
        shadow(color: .ink.opacity(0.04), radius: 2, y: 2)
            .shadow(color: .ink.opacity(0.16), radius: 32, y: 22)
    }
}
