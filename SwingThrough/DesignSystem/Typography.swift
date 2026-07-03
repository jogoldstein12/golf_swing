// Type system: Instrument Serif for the editorial voice (wordmark, hero numerals,
// pull-quotes), Satoshi for every UI label and technical readout. Deliberately not
// SF / Inter / Geist.
import SwiftUI

public enum Type {
    public static func display(_ size: CGFloat) -> Font {
        .custom("InstrumentSerif-Regular", size: size)
    }
    public static func displayItalic(_ size: CGFloat) -> Font {
        .custom("InstrumentSerif-Italic", size: size)
    }

    public enum UIWeight { case regular, medium, bold, black }
    public static func ui(_ size: CGFloat, _ weight: UIWeight = .regular) -> Font {
        switch weight {
        case .regular: .custom("Satoshi-Regular", size: size)
        case .medium: .custom("Satoshi-Medium", size: size)
        case .bold: .custom("Satoshi-Bold", size: size)
        case .black: .custom("Satoshi-Black", size: size)
        }
    }
}

/// Tiny uppercase letter-spaced micro-label — the editorial system's caption voice.
public struct MicroLabel: View {
    let text: String
    var color: Color = .ink45
    var size: CGFloat = 10

    public init(_ text: String, color: Color = .ink45, size: CGFloat = 10) {
        self.text = text
        self.color = color
        self.size = size
    }

    public var body: some View {
        Text(text.uppercased())
            .font(Type.ui(size, .bold))
            .tracking(size * 0.2)
            .foregroundStyle(color)
    }
}
