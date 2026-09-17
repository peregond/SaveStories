import SwiftUI

// Use system glass for controls; content cards retain their readable surfaces.
private struct SaveMeGlassButtonModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    let prominent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26, *), !reduceTransparency, contrast != .increased {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

extension View {
    func saveMeGlassButton(prominent: Bool = false) -> some View {
        modifier(SaveMeGlassButtonModifier(prominent: prominent))
    }

    @ViewBuilder
    func saveMeExtendedBackground(enabled: Bool) -> some View {
        if #available(macOS 26, *) {
            backgroundExtensionEffect(isEnabled: enabled)
        } else {
            self
        }
    }
}

struct SaveMeGlassGroup<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    let spacing: CGFloat
    @ViewBuilder var content: Content

    @ViewBuilder
    var body: some View {
        if #available(macOS 26, *), !reduceTransparency, contrast != .increased {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
