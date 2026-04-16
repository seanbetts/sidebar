import SwiftUI

func sidebarPanelHeaderUsesStandaloneBackground() -> Bool {
    false
}

func sidebarPanelListUsesStandaloneBackground() -> Bool {
    false
}

func sidebarPanelHeaderInlineSearchShadowBleed(showsInlineSearch: Bool) -> CGFloat {
    guard showsInlineSearch else {
        return 0
    }

    return LayoutMetrics.inlineSearchFieldBottomShadowBleed
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

func sidebarHiddenProminentSectionHeader(_ title: String) -> some View {
    sidebarProminentSectionHeader(title)
        .hidden()
        .accessibilityHidden(true)
}

@ViewBuilder
func sidebarPanelList<SelectionValue: Hashable, Content: View>(
    selection: Binding<SelectionValue?>? = nil,
    @ViewBuilder content: () -> Content
) -> some View {
#if os(macOS)
    if let selection {
        List(selection: selection) {
            content()
        }
    } else {
        List {
            content()
        }
    }
#else
    List {
        content()
    }
#endif
}

@ViewBuilder
func sidebarPanelList<Content: View>(
    @ViewBuilder content: () -> Content
) -> some View {
#if os(macOS)
    List {
        content()
    }
#else
    List {
        content()
    }
#endif
}

extension View {
    func sidebarPanelScaffoldBackground() -> some View {
        background(PlatformTokens.sidebarPanelBackground)
    }

    @ViewBuilder
    func sidebarPanelHeaderBackground(showsInlineSearch: Bool = false) -> some View {
        let header = padding(.bottom, sidebarPanelHeaderInlineSearchShadowBleed(showsInlineSearch: showsInlineSearch))

        if sidebarPanelHeaderUsesStandaloneBackground() {
            header.background(PlatformTokens.panelHeaderBackground)
        } else {
            header
        }
    }

    @ViewBuilder
    func sidebarPanelListBackground() -> some View {
        if sidebarPanelListUsesStandaloneBackground() {
            background(PlatformTokens.sidebarPanelBackground)
        } else {
            self
        }
    }

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
