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
    @State private var savePillState: SettingsSavePillState?
    @State private var wasSaving = false
    @State private var savingDelayTask: Task<Void, Never>?
    @State private var hideSavedTask: Task<Void, Never>?

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
                settingsBackground: settingsBackground,
                savePillState: savePillState
            )
            #endif
        }
        #if os(macOS)
        .overlay(alignment: .bottom) {
            if let savePillState {
                SettingsSaveStatusPill(state: savePillState)
                    .padding(.horizontal, DesignTokens.Spacing.lg)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        #endif
        .animation(.easeInOut(duration: DesignTokens.Animation.standard), value: savePillState)
        .onAppear {
            updateSavePillState()
        }
        .onChange(of: saveStatusSignature) { _, _ in
            updateSavePillState()
        }
        .onDisappear {
            savingDelayTask?.cancel()
            hideSavedTask?.cancel()
        }
    }

    private var settingsBackground: Color {
        colorScheme == .dark ? DesignTokens.Colors.background : DesignTokens.Colors.surface
    }

    private var listBackground: Color {
        colorScheme == .dark ? DesignTokens.Colors.surface : DesignTokens.Colors.background
    }

    private var isSavingAnySettings: Bool {
        let viewModel = environment.settingsViewModel
        return viewModel.isSavingProfile
            || viewModel.isSavingSystem
            || viewModel.isSavingSkills
            || viewModel.isSavingPrimaryProvider
    }

    private var currentSaveError: String? {
        let viewModel = environment.settingsViewModel
        return viewModel.profileSaveError
            ?? viewModel.systemSaveError
            ?? viewModel.skillsError
            ?? viewModel.primaryProviderError
    }

    private var saveStatusSignature: String {
        "\(isSavingAnySettings)|\(currentSaveError ?? "")"
    }

    private func updateSavePillState() {
        let isSaving = isSavingAnySettings
        let saveError = currentSaveError?.trimmingCharacters(in: .whitespacesAndNewlines)

        defer {
            wasSaving = isSaving
        }

        if let saveError, !saveError.isEmpty {
            savingDelayTask?.cancel()
            hideSavedTask?.cancel()
            withAnimation {
                savePillState = .error
            }
            return
        }

        if isSaving {
            hideSavedTask?.cancel()
            if case .saving = savePillState {
                return
            }
            savingDelayTask?.cancel()
            savingDelayTask = Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                guard isSavingAnySettings, currentSaveError == nil else { return }
                await MainActor.run {
                    withAnimation {
                        savePillState = .saving
                    }
                }
            }
            return
        }

        savingDelayTask?.cancel()

        if wasSaving {
            showSavedPill()
            return
        }

        if savePillState != nil {
            withAnimation {
                savePillState = nil
            }
        }
    }

    private func showSavedPill() {
        hideSavedTask?.cancel()
        withAnimation {
            savePillState = .saved
        }
        hideSavedTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation {
                    if case .saved = savePillState {
                        savePillState = nil
                    }
                }
            }
        }
    }
}

private enum SettingsSavePillState {
    case saving
    case saved
    case error
}

private struct SettingsSaveStatusPill: View {
    let state: SettingsSavePillState

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            switch state {
            case .saving:
                ProgressView()
                    .controlSize(.small)
                    .tint(.primary)
            case .saved:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.primary)
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(DesignTokens.Colors.error)
            }
            Text(title)
                .font(DesignTokens.Typography.labelMd)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.xsPlus)
        .glassEffect(.regular.interactive(), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }

    private var title: String {
        switch state {
        case .saving:
            return "Saving settings..."
        case .saved:
            return "Saved"
        case .error:
            return "Couldn’t save settings"
        }
    }
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
            return "Other"
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
            return "command.circle.fill"
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
                    Label("Agent", systemImage: "brain.fill")
                }
            settingsTabContent(SkillsSettingsView(viewModel: viewModel))
                .tabItem {
                    Label("Skills", systemImage: "command.circle.fill")
                }
            settingsTabContent(MemoriesSettingsView(viewModel: memoriesViewModel))
                .tabItem {
                    Label("Memories", systemImage: "bookmark")
                }
            settingsTabContent(GeneralSettingsView())
                .tabItem {
                    Label("Other", systemImage: "gearshape")
                }
        }
        .padding(DesignTokens.Spacing.md)
        .background(settingsBackground)
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
