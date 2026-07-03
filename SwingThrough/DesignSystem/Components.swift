// Core components shared across screens.
import SwiftUI

/// Paper card floating on the bone canvas.
public struct FloatCard<Content: View>: View {
    var padding: CGFloat
    @ViewBuilder var content: () -> Content

    public init(padding: CGFloat = 24, @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding
        self.content = content
    }

    public var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color.paper)
            )
            .floatShadow()
    }
}

/// The single primary action: an ink pill.
public struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    @GestureState private var pressed = false

    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(Type.ui(15, .medium))
                .tracking(0.4)
                .foregroundStyle(Color.bone)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Capsule().fill(Color.ink))
        }
        .buttonStyle(PressScaleStyle())
    }
}

/// Gentle physical press feedback used on all tappables.
public struct PressScaleStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

/// Hairline divider.
public struct Hairline: View {
    public init() {}
    public var body: some View {
        Rectangle().fill(Color.ink08).frame(height: 1)
    }
}

public extension View {
    /// Warm grain. Apply to opaque, pure-SwiftUI layers only (e.g. the bone canvas
    /// color) — colorEffect silently blanks UIKit-backed content like ScrollView.
    func grain(_ intensity: Double = 0.05) -> some View {
        colorEffect(ShaderLibrary.grain(.float(Float(intensity))))
    }
}
