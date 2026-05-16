import SwiftUI
import sideBarShared

public struct SidebarRail: View {
    private static let logoSize: CGFloat = 26

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
        VStack(spacing: DesignTokens.Spacing.md) {
            Button(
                action: { onTogglePanel?() },
                label: {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: Self.logoSize, height: Self.logoSize)
                        .frame(width: DesignTokens.Icon.xl, height: DesignTokens.Icon.xl)
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

            VStack(spacing: DesignTokens.Spacing.sm) {
                ForEach(sections) { section in
                    sectionButton(for: section)
                }
            }

            Spacer()

            sectionButton(for: .skillsStore)

            Button(
                action: { onShowSettings?() },
                label: {
                    ProfileAvatarView(size: DesignTokens.Icon.xl)
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
        .frame(width: DesignTokens.Size.railWidth)
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
            guard Self.shouldLoadProfileImageOnAppear(
                isAuthenticated: environment.isAuthenticated,
                profileImageUrl: environment.settingsViewModel.settings?.profileImageUrl,
                hasProfileImageData: environment.settingsViewModel.profileImageData != nil
            ) else {
                StartupDebugTrace.log(
                    "sidebar-rail.profile-image.skip",
                    details: [
                        "has_profile_image_data":
                            environment.settingsViewModel.profileImageData == nil ? "false" : "true",
                        "has_profile_image_url":
                            environment.settingsViewModel.settings?.profileImageUrl?.trimmedOrNil == nil
                            ? "false"
                            : "true",
                        "is_authenticated": environment.isAuthenticated ? "true" : "false"
                    ]
                )
                return
            }

            StartupDebugTrace.log("sidebar-rail.profile-image.start")
            Task {
                await environment.settingsViewModel.loadProfileImage()
            }
        }
    }

    static func shouldLoadProfileImageOnAppear(
        isAuthenticated: Bool,
        profileImageUrl: String?,
        hasProfileImageData: Bool
    ) -> Bool {
        guard isAuthenticated, !hasProfileImageData else { return false }
        return profileImageUrl?.trimmedOrNil != nil
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
            Image(appIcon: section.appIcon)
                .appFont(.titleSm)
                .scaleEffect(iconScale(for: section))
                .frame(width: DesignTokens.Icon.xl, height: DesignTokens.Icon.xl)
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
                .frame(width: DesignTokens.Icon.xl, height: DesignTokens.Icon.xl)
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
