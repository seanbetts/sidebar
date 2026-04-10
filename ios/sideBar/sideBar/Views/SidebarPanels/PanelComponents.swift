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
    func sidebarPanelListStyle(
        reducesCompactPhoneSectionHeaderGap: Bool = false
    ) -> some View {
#if os(macOS)
        self.listStyle(.sidebar)
#else
        if reducesCompactPhoneSectionHeaderGap {
            self
                .listStyle(.plain)
                .environment(
                    \.defaultMinListHeaderHeight,
                    LayoutMetrics.compactPhonePanelSectionHeaderMinHeight
                )
        } else {
            self.listStyle(.plain)
        }
#endif
    }

    @ViewBuilder
    func sidebarCompactPhoneTopPadding(
        _ padding: CGFloat,
        isCompactPhone: Bool
    ) -> some View {
#if os(macOS)
        self
#else
        if isCompactPhone {
            self.padding(.top, padding)
        } else {
            self
        }
#endif
    }
}
