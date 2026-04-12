import SwiftUI

public struct SidebarRail: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Binding private var selection: AppSection?
    @State private var hoveredSection: AppSection?
    @State private var isLogoHovered = false
    @State private var isSettingsHovered = false
    private let onTogglePanel: (() -> Void)?
    private let onShowSettings: (() -> Void)?
    private let onSelectSection: ((AppSection) -> Void)?

    private let sections: [AppSection] = AppSection.primaryNavigationSections.filter {
        $0 != .skillsStore
    }

    public init(
        selection: Binding<AppSection?>,
        onTogglePanel: (() -> Void)? = nil,
        onShowSettings: (() -> Void)? = nil,
        onSelectSection: ((AppSection) -> Void)? = nil
    ) {
        self._selection = selection
        self.onTogglePanel = onTogglePanel
        self.onShowSettings = onShowSettings
        self.onSelectSection = onSelectSection
    }

    public var body: some View {
        VStack(spacing: 16) {
            Button(
                action: { onTogglePanel?() },
                label: {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 26, height: 26)
                        .frame(width: 32, height: 32)
                        .background {
                            SidebarRailButtonBackground(
                                chrome: Self.buttonChrome(isActive: false, isHovered: isLogoHovered),
                                opacity: Self.buttonChromeOpacity(isActive: false, isHovered: isLogoHovered)
                            )
                        }
                }
            )
            .buttonStyle(.plain)
            .accessibilityLabel("Toggle sidebar")
            .sidebarHover($isLogoHovered)

            VStack(spacing: 12) {
                ForEach(sections) { section in
                    sectionButton(for: section)
                }
            }

            Spacer()

            sectionButton(for: .skillsStore)

            Button(
                action: { onShowSettings?() },
                label: {
                    ProfileAvatarView(size: 32)
                        .background {
                            SidebarRailButtonBackground(
                                chrome: Self.buttonChrome(isActive: false, isHovered: isSettingsHovered),
                                opacity: Self.buttonChromeOpacity(isActive: false, isHovered: isSettingsHovered)
                            )
                        }
                }
            )
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .sidebarHover($isSettingsHovered)
        }
        .frame(width: 56)
        .frame(maxHeight: .infinity)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(
            Rectangle()
                .fill(railBackground)
                .ignoresSafeArea(.all, edges: .bottom)
                .overlay(
                    Rectangle()
                        .fill(separatorColor)
                        .frame(width: 1)
                        .ignoresSafeArea(.all, edges: .bottom),
                    alignment: .trailing
                )
        )
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear {
            guard environment.isAuthenticated,
                  environment.settingsViewModel.profileImageData == nil else { return }
            Task {
                if environment.settingsViewModel.settings == nil {
                    await environment.settingsViewModel.load()
                }
                await environment.settingsViewModel.loadProfileImage()
            }
        }
    }

    private func sectionButton(for section: AppSection) -> some View {
        let isActive = selection == section
        let isHovered = hoveredSection == section

        return Button {
            if let onSelectSection {
                onSelectSection(section)
            } else {
                selection = section
            }
        } label: {
            Image(systemName: iconName(for: section))
                .font(.system(size: 18, weight: .semibold))
                .scaleEffect(iconScale(for: section))
                .frame(width: 32, height: 32)
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                .background {
                    SidebarRailButtonBackground(
                        chrome: Self.buttonChrome(isActive: isActive, isHovered: isHovered),
                        opacity: Self.buttonChromeOpacity(isActive: isActive, isHovered: isHovered)
                    )
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.title)
        .accessibilityValue(isActive ? "Selected" : "")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .sidebarHover(
            Binding(
                get: { hoveredSection == section },
                set: { isHovering in
                    hoveredSection = isHovering ? section : nil
                }
            )
        )
    }

    private func iconName(for section: AppSection) -> String {
        switch section {
        case .chat:
            return "bubble"
        case .notes:
            return "text.document"
        case .files:
            return "folder"
        case .websites:
            return "globe"
        case .tasks:
            return "checkmark.square"
        case .skillsStore:
            return "command.circle"
        default:
            return "square.grid.2x2"
        }
    }

    static func buttonChrome(isActive: Bool, isHovered: Bool) -> GlassChrome.Kind? {
        guard isActive || isHovered else {
            return nil
        }

        return .actionButton
    }

    static func buttonChromeOpacity(isActive: Bool, isHovered: Bool) -> Double {
        if isActive {
            return 1
        }
        if isHovered {
            return 0.72
        }
        return 0
    }

    private var railBackground: Color {
        DesignTokens.Colors.sidebar
    }

    private var separatorColor: Color {
        #if os(macOS)
        return Color(nsColor: .separatorColor)
        #else
        return Color(.separator)
        #endif
    }

    private func iconScale(for section: AppSection) -> CGFloat {
        section == .skillsStore ? 1.2 : 1.0
    }

}

private struct SidebarRailButtonBackground: View {
    let chrome: GlassChrome.Kind?
    let opacity: Double

    var body: some View {
        if chrome != nil {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                .fill(backgroundColor)
                .frame(width: 32, height: 32)
                .opacity(opacity)
        }
    }

    private var backgroundColor: Color {
        if opacity >= 1 {
            return DesignTokens.Colors.selection
        }
        return DesignTokens.Colors.sidebarHoverBackground
    }
}
