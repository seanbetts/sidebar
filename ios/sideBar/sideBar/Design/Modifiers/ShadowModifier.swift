import SwiftUI

struct AppShadowModifier: ViewModifier {
    let color: Color
    let radius: CGFloat
    let xOffset: CGFloat
    let yOffset: CGFloat

    func body(content: Content) -> some View {
        content.shadow(color: color, radius: radius, x: xOffset, y: yOffset)
    }
}

extension View {
    func appShadow(
        color: Color,
        radius: CGFloat,
        x xOffset: CGFloat = 0,
        y yOffset: CGFloat = 0
    ) -> some View {
        modifier(AppShadowModifier(color: color, radius: radius, xOffset: xOffset, yOffset: yOffset))
    }
}
