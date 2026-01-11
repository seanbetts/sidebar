import SwiftUI

struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(materialBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                    .stroke(DesignTokens.Colors.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
    }

    private var materialBackground: some View {
        #if os(macOS)
        return RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
            .fill(.regularMaterial)
        #else
        return RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
            .fill(.ultraThinMaterial)
        #endif
    }
}
