import SwiftUI

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
    let savePillState: SettingsSavePillState?
    @State private var hasLoaded = false

    var body: some View {
        TabView {
            settingsTabContent(ProfileSettingsView(viewModel: viewModel))
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
            settingsTabContent(UserSettingsView(viewModel: viewModel))
                .tabItem {
                    Label("User", systemImage: "person.line.dotted.person")
                }
            settingsTabContent(AgentSettingsView(viewModel: viewModel))
                .tabItem {
                    Label(viewModel.assistantDisplayName, systemImage: "brain.fill")
                }
            settingsTabContent(SkillsSettingsView(viewModel: viewModel))
                .tabItem {
                    Label("Skills", systemImage: "command.circle")
                }
            settingsTabContent(MemoriesSettingsView(viewModel: memoriesViewModel))
                .tabItem {
                    Label("Memories", systemImage: "bookmark")
                }
            settingsTabContent(GeneralSettingsView())
                .tabItem {
                    Label("App", systemImage: "gearshape")
                }
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.Colors.settingsBackground)
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
            .appFont(.subheadline)
            .overlay(alignment: .bottom) {
                if let savePillState {
                    SettingsSaveStatusPill(state: savePillState)
                        .padding(.horizontal, DesignTokens.Spacing.lg)
                        .padding(.bottom, DesignTokens.Spacing.sm)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
    }
}
