import SwiftUI

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(DesignTokens.Spacing.md)
            .glassChrome(.card)
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardModifier())
    }
}
