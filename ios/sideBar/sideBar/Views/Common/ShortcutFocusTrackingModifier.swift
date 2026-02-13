import SwiftUI

struct ShortcutFocusTrackingModifier: ViewModifier {
    @EnvironmentObject private var environment: AppEnvironment
    let section: AppSection?

    func body(content: Content) -> some View {
        #if os(macOS)
        content.simultaneousGesture(
            TapGesture().onEnded {
                guard let section else { return }
                environment.focusedSection = section
            }
        )
        #else
        content
        #endif
    }
}

extension View {
    func trackShortcutFocus(section: AppSection?) -> some View {
        modifier(ShortcutFocusTrackingModifier(section: section))
    }
}
