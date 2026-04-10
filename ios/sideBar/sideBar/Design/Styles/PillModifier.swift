import SwiftUI

struct PillModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .glassChrome(.pill)
    }
}

extension View {
    func pillStyle() -> some View {
        modifier(PillModifier())
    }
}
