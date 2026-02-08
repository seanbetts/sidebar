import SwiftUI
import LocalAuthentication
#if os(macOS)
import UniformTypeIdentifiers
#endif
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - SettingsView

public struct SettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme

    public init() {
    }

    public var body: some View {
        ZStack {
            settingsBackground
                .ignoresSafeArea()
            #if os(macOS)
            SettingsSplitView(
                viewModel: environment.settingsViewModel,
                memoriesViewModel: environment.memoriesViewModel,
                settingsBackground: settingsBackground,
                listBackground: listBackground
            )
            #else
            SettingsTabsView(
                viewModel: environment.settingsViewModel,
                memoriesViewModel: environment.memoriesViewModel,
                settingsBackground: settingsBackground
            )
            #endif
        }
    }

    private var settingsBackground: Color {
        colorScheme == .dark ? DesignTokens.Colors.background : DesignTokens.Colors.surface
    }

    private var listBackground: Color {
        colorScheme == .dark ? DesignTokens.Colors.surface : DesignTokens.Colors.background
    }
}

#if os(macOS)
private enum SettingsSection: String, CaseIterable, Identifiable {
    case profile
    case settings
    case system
    case skills
    case memories

    var id: String { rawValue }

    var title: String {
        switch self {
        case .profile:
            return "Profile"
        case .settings:
            return "Settings"
        case .system:
            return "System"
        case .skills:
            return "Skills"
        case .memories:
            return "Memories"
        }
    }

    var systemImage: String {
        switch self {
        case .profile:
            return "person.crop.circle"
        case .settings:
            return "gearshape"
        case .system:
            return "bubble"
        case .skills:
            return "hammer.circle"
        case .memories:
            return "bookmark"
        }
    }
}

private struct SettingsSplitView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var memoriesViewModel: MemoriesViewModel
    let settingsBackground: Color
    let listBackground: Color
    @State private var selection: SettingsSection? = .profile
    @State private var hasLoaded = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(listBackground)
            .modifier(SidebarToggleHider())
        } detail: {
            settingsDetailView(for: selection ?? .profile)
                .navigationTitle(selection?.title ?? "Settings")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .modifier(SidebarToggleHider())
                .background(settingsBackground)
        }
        .navigationSplitViewStyle(.balanced)
        .modifier(SidebarToggleHider())
        .frame(minWidth: 680, minHeight: 460)
        .background(settingsBackground)
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

    @ViewBuilder
    private func settingsDetailView(for section: SettingsSection) -> some View {
        switch section {
        case .profile:
            ProfileSettingsView(viewModel: viewModel)
        case .settings:
            GeneralSettingsView()
        case .system:
            SystemSettingsView(viewModel: viewModel)
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
}
#endif

#if os(macOS)
private struct SidebarToggleHider: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 13.0, *) {
            content.toolbar(removing: .sidebarToggle)
        } else {
            content
        }
    }
}
#endif

private struct SettingsTabsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var memoriesViewModel: MemoriesViewModel
    let settingsBackground: Color
    @State private var hasLoaded = false

    var body: some View {
        TabView {
            ProfileSettingsView(viewModel: viewModel)
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
            GeneralSettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
            SystemSettingsView(viewModel: viewModel)
                .tabItem {
                    Label("System", systemImage: "bubble")
                }
            SkillsSettingsView(viewModel: viewModel)
                .tabItem {
                    Label("Skills", systemImage: "hammer.circle")
                }
            MemoriesSettingsView(viewModel: memoriesViewModel)
                .tabItem {
                    Label("Memories", systemImage: "bookmark")
                }
        }
        .padding(DesignTokens.Spacing.md)
        .background(settingsBackground)
        .ignoresSafeArea()
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
}
