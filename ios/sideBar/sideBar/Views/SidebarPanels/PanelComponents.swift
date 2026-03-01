import SwiftUI

func panelHeaderBackground() -> Color {
    PlatformTokens.panelHeaderBackground
}

func sidebarSectionHeader(_ title: String) -> some View {
    Text(title)
        .appFont(.caption)
}

func sidebarProminentSectionHeader(_ title: String) -> some View {
    Text(title)
        .appFont(SidebarTypography.sectionHeader)
        .foregroundStyle(.secondary)
        .textCase(nil)
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
