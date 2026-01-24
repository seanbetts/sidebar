import SwiftUI
#if os(macOS)
import AppKit
#endif

public struct SidebarRail: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Binding private var selection: AppSection?
    @State private var hoveredSection: AppSection?
    private let onTogglePanel: (() -> Void)?
    private let onShowSettings: (() -> Void)?
    private let onSelectSection: ((AppSection) -> Void)?

    private let sections: [AppSection] = [
        .notes,
        .tasks,
        .websites,
        .files,
        .chat
    ]

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
                    Image(systemName: "sidebar.left")
                        .font(DesignTokens.Typography.titleLg)
                        .frame(width: 32, height: 32)
                }
            )
            .buttonStyle(.plain)
            .accessibilityLabel("Toggle sidebar")

            VStack(spacing: 12) {
                ForEach(sections) { section in
                    sectionButton(for: section)
                }
            }

            Spacer()

            #if os(macOS)
            SettingsLink {
                ProfileAvatarView(size: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            #else
            Button(
                action: { onShowSettings?() },
                label: {
                    ProfileAvatarView(size: 32)
                }
            )
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            #endif
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
                .font(DesignTokens.Typography.titleLg)
                .frame(width: 32, height: 32)
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(buttonBackground(isActive: isActive, isHovered: isHovered))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.title)
        .accessibilityValue(isActive ? "Selected" : "")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        #if os(macOS)
        .onHover { isHovering in
            hoveredSection = isHovering ? section : nil
        }
        #endif
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
        default:
            return "square.grid.2x2"
        }
    }

    private func buttonBackground(isActive: Bool, isHovered: Bool) -> Color {
        if isActive {
            return Color.accentColor.opacity(0.18)
        }
        if isHovered {
            return Color.primary.opacity(0.08)
        }
        return Color.clear
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

}
