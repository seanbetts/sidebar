import SwiftUI
import LocalAuthentication
#if os(macOS)
import UniformTypeIdentifiers
#endif
#if os(macOS)
import AppKit
#endif

// MARK: - SettingsView

public enum SettingsPresentationStyle: Equatable {
    case standalone
    case macModal
}

public struct SettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    private let presentationStyle: SettingsPresentationStyle
    private let onClose: (() -> Void)?

    public init(
        presentationStyle: SettingsPresentationStyle = .standalone,
        onClose: (() -> Void)? = nil
    ) {
        self.presentationStyle = presentationStyle
        self.onClose = onClose
    }

    public var body: some View {
        let content = ZStack {
            DesignTokens.Colors.settingsBackground
                .ignoresSafeArea()
            #if os(macOS)
            SettingsSplitView(
                viewModel: environment.settingsViewModel,
                memoriesViewModel: environment.memoriesViewModel
            )
            #else
            SettingsTabsView(
                viewModel: environment.settingsViewModel,
                memoriesViewModel: environment.memoriesViewModel
            )
            #endif
        }
        .appTextSize()

        #if os(macOS)
        switch presentationStyle {
        case .standalone:
            content
        case .macModal:
            MacModalShell(type: settingsMacPresentationPanelType()) {
                VStack(spacing: 0) {
                    settingsInspectorHeader

                    Divider()

                    content
                }
            }
            .frame(maxWidth: macModalFrameWidth(for: settingsMacPresentationPanelType()), maxHeight: 760)
            .onExitCommand {
                onClose?()
            }
        }
        #else
        content
        #endif
    }

    #if os(macOS)
    private var settingsInspectorHeader: some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Settings")
                    .appFont(.subheading)
                Text("Tune sideBar for your workspace and assistant.")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: DesignTokens.Spacing.md)

            Button {
                onClose?()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close settings")
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
        .frame(height: LayoutMetrics.appHeaderMinHeight)
    }
    #endif
}

#if os(macOS)
private enum SettingsSection: String, CaseIterable, Identifiable {
    case profile
    case user
    case agent
    case skills
    case memories
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .profile:
            return "Profile"
        case .settings:
            return "App"
        case .user:
            return "User"
        case .agent:
            return "Agent"
        case .skills:
            return "Skills"
        case .memories:
            return "Memories"
        }
    }

    func displayTitle(assistantDisplayName: String) -> String {
        if self == .agent {
            return assistantDisplayName
        }
        return title
    }

    var systemImage: String {
        switch self {
        case .profile:
            return "person.crop.circle"
        case .settings:
            return "gearshape"
        case .user:
            return "person.line.dotted.person"
        case .agent:
            return "brain.fill"
        case .skills:
            return "command.circle"
        case .memories:
            return "bookmark"
        }
    }
}

private struct SettingsSplitView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var memoriesViewModel: MemoriesViewModel
    @AppStorage(AppStorageKeys.settingsSelectedSection) private var selectionRaw = SettingsSection.profile.rawValue
    @State private var hasLoaded = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(spacing: 0) {
                settingsSidebarHeader

                List(SettingsSection.allCases, selection: selectionBinding) { section in
                    Label(section.displayTitle(assistantDisplayName: viewModel.assistantDisplayName), systemImage: section.systemImage)
                        .appFont(.subheading)
                        .padding(.vertical, DesignTokens.Spacing.xxsPlus)
                        .tag(section)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(DesignTokens.Colors.settingsFormBackground)
            }
            .frame(minWidth: settingsMacSidebarWidth(), idealWidth: settingsMacSidebarWidth(), maxWidth: settingsMacSidebarWidth() + 12)
            .background(DesignTokens.Colors.settingsFormBackground)
            .modifier(SidebarToggleHider())
        } detail: {
            settingsDetailView(for: selectedSection)
                .appFont(.subheading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .modifier(SidebarToggleHider())
                .background(DesignTokens.Colors.settingsBackground)
        }
        .navigationSplitViewStyle(.balanced)
        .modifier(SidebarToggleHider())
        .frame(minWidth: 680, minHeight: 460)
        .background(DesignTokens.Colors.settingsBackground)
        .onAppear {
            if !hasLoaded {
                hasLoaded = true
                Task {
                    await loadSettings()
                }
            }
        }
        .onChange(of: columnVisibility) { _, newValue in
            if newValue != .all {
                columnVisibility = .all
            }
        }
    }

    private var settingsSidebarHeader: some View {
        VStack(alignment: .leading, spacing: settingsMacSectionIntroSpacing()) {
            Text("Settings")
                .appFont(.subheading)
            Text("Choose a section to configure your workspace, profile, and assistant.")
                .appFont(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.top, DesignTokens.Spacing.md)
        .padding(.bottom, DesignTokens.Spacing.sm)
        .background(DesignTokens.Colors.settingsFormBackground)
    }

    @ViewBuilder
    private func settingsDetailView(for section: SettingsSection) -> some View {
        switch section {
        case .profile:
            ProfileSettingsView(viewModel: viewModel)
        case .settings:
            GeneralSettingsView()
        case .user:
            UserSettingsView(viewModel: viewModel)
        case .agent:
            AgentSettingsView(viewModel: viewModel)
        case .skills:
            SkillsSettingsView(viewModel: viewModel)
        case .memories:
            MemoriesSettingsView(viewModel: memoriesViewModel)
        }
    }

    private func loadSettings() async {
        await viewModel.load()
        await viewModel.loadSkills()
        await viewModel.loadShortcutsToken()
        await viewModel.loadProfileImage()
    }

    private var selectedSection: SettingsSection {
        SettingsSection(rawValue: selectionRaw) ?? .profile
    }

    private var selectionBinding: Binding<SettingsSection?> {
        Binding(
            get: { SettingsSection(rawValue: selectionRaw) },
            set: { selectionRaw = ($0 ?? .profile).rawValue }
        )
    }
}
#endif
