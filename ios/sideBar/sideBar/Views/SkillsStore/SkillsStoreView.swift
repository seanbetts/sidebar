import SwiftUI

public struct SkillsStorePanel: View {
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    public init() {
    }

    public var body: some View {
        Group {
            if isCompact {
                SkillsStoreView()
            } else {
                SidebarPanelPlaceholder(
                    title: "Skills Store",
                    subtitle: "Browse and install skills in the main workspace."
                )
            }
        }
    }

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        horizontalSizeClass == .compact
        #endif
    }
}
