import SwiftUI

struct ShortcutFocusTrackingModifier: ViewModifier {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.workspaceColumn) private var workspaceColumn
    let section: AppSection?

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            TapGesture().onEnded {
                environment.focusedWorkspacePane = workspaceColumn.workspacePane
                if let section {
                    environment.focusedSection = section
                }
            }
        )
    }
}

extension View {
    func trackShortcutFocus(section: AppSection?) -> some View {
        modifier(ShortcutFocusTrackingModifier(section: section))
    }
}
