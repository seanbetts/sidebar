import SwiftUI

struct BorderedModifier: ViewModifier {
    let color: Color
    let lineWidth: CGFloat
    let cornerRadius: CGFloat
    let style: RoundedCornerStyle

    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: style)
                .stroke(color, lineWidth: lineWidth)
        )
    }
}

extension View {
    func bordered(
        color: Color = DesignTokens.Colors.border,
        lineWidth: CGFloat = 1,
        cornerRadius: CGFloat = DesignTokens.Radius.sm,
        style: RoundedCornerStyle = .continuous
    ) -> some View {
        modifier(
            BorderedModifier(
                color: color,
                lineWidth: lineWidth,
                cornerRadius: cornerRadius,
                style: style
            )
        )
    }
}
