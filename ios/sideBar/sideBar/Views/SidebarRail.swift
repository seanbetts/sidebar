import SwiftUI

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
            Button(action: { onTogglePanel?() }) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

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
            #else
            Button(action: { onShowSettings?() }) {
                ProfileAvatarView(size: 32)
            }
            .buttonStyle(.plain)
            #endif
        }
        .frame(width: 56)
        .padding(.vertical, 12)
        .background(railBackground)
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
                .frame(width: 32, height: 32)
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(buttonBackground(isActive: isActive, isHovered: isHovered))
                )
        }
        .buttonStyle(.plain)
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
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color.platformSecondarySystemBackground
        #endif
    }

}
