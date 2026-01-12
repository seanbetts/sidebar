import SwiftUI

struct StaggeredAppearance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let index: Int
    let isActive: Bool

    func body(content: Content) -> some View {
        let animation = Motion.standard(reduceMotion: reduceMotion)?
            .delay(Double(index) * 0.03)

        return content
            .opacity(isActive ? 1 : 0)
            .offset(y: isActive ? 0 : 6)
            .animation(animation, value: isActive)
    }
}

extension View {
    func staggeredAppear(index: Int, isActive: Bool) -> some View {
        modifier(StaggeredAppearance(index: index, isActive: isActive))
    }
}
