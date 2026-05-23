import SwiftUI
import sideBarShared

#if os(macOS)
struct SidebarToggleHider: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 13.0, *) {
            content.toolbar(removing: .sidebarToggle)
        } else {
            content
        }
    }
}
#endif

struct SettingsTabsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var memoriesViewModel: MemoriesViewModel
    @State private var hasLoaded = false
    @AppStorage(AppStorageKeys.settingsSelectedTab) private var selectedTabRaw = Tab.profile.rawValue

    var body: some View {
        TabView(selection: $selectedTabRaw) {
            settingsTabContent(ProfileSettingsView(viewModel: viewModel))
                .tag(Tab.profile.rawValue)
                .tabItem {
                    Label("Profile", systemImage: AppIcon.Settings.profile.rawValue)
                }
            settingsTabContent(UserSettingsView(viewModel: viewModel))
                .tag(Tab.user.rawValue)
                .tabItem {
                    Label("User", systemImage: AppIcon.Settings.user.rawValue)
                }
            settingsTabContent(AgentSettingsView(viewModel: viewModel))
                .tag(Tab.agent.rawValue)
                .tabItem {
                    Label(viewModel.assistantDisplayName, systemImage: AppIcon.Settings.assistant.rawValue)
                }
            settingsTabContent(SkillsSettingsView(viewModel: viewModel))
                .tag(Tab.skills.rawValue)
                .tabItem {
                    Label("Skills", systemImage: AppIcon.Settings.skills.rawValue)
                }
            settingsTabContent(
                SettingsMoreTabView(
                    memoriesViewModel: memoriesViewModel
                )
            )
                .tag(Tab.more.rawValue)
                .tabItem {
                    Label("More", systemImage: AppIcon.Settings.more.rawValue)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if !hasLoaded {
                hasLoaded = true
                Task {
                    await loadSettings()
                }
            }
        }
    }

    private func loadSettings() async {
        await viewModel.load()
        await viewModel.loadSkills()
        await viewModel.loadShortcutsToken()
        await viewModel.loadProfileImage()
    }

    @ViewBuilder
    private func settingsTabContent<Content: View>(_ content: Content) -> some View {
        content
            .appFont(.body)
    }
}

private extension SettingsTabsView {
    enum Tab: String {
        case profile
        case user
        case agent
        case skills
        case more
    }
}
