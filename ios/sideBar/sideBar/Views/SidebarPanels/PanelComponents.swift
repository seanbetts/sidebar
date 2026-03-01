import SwiftUI

func panelHeaderBackground() -> Color {
    PlatformTokens.panelHeaderBackground
}

func sidebarSectionHeader(_ title: String) -> some View {
    Text(title)
        .appFont(.caption)
}

extension View {
    @ViewBuilder
    func sidebarPanelListStyle() -> some View {
#if os(macOS)
        self.listStyle(.sidebar)
#else
        self.listStyle(.plain)
#endif
    }
}
