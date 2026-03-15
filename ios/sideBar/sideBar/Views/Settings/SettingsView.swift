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
    @State private var savePillState: SettingsSavePillState?
    @State private var wasSaving = false
    @State private var savingDelayTask: Task<Void, Never>?
    @State private var hideSavedTask: Task<Void, Never>?
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
                memoriesViewModel: environment.memoriesViewModel,
                savePillState: savePillState
            )
            #endif
        }
        .appTextSize()
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
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 32, y: 18)
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
                    .appFont(.headline)
                Text("Tune sideBar for your workspace and assistant.")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: DesignTokens.Spacing.md)

            inlineSaveStatusView

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
    }

    @ViewBuilder
    private var inlineSaveStatusView: some View {
        if let savePillState {
            SettingsSaveStatusPill(state: savePillState)
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }
    #endif

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
        defer { wasSaving = isSaving }

        let timeline = SettingsSaveStatusLogic.timeline(
            wasSaving: wasSaving,
            isSaving: isSaving,
            saveError: saveError
        )

        switch timeline.immediateState {
        case .error:
            savingDelayTask?.cancel()
            hideSavedTask?.cancel()
            withAnimation { savePillState = .error }
        case .saving:
            startSavingDelay()
        case .saved:
            showSavedPill()
        case nil:
            savingDelayTask?.cancel()
            if savePillState != nil {
                withAnimation { savePillState = nil }
            }
        }
    }

    private func startSavingDelay() {
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
    }

    private func showSavedPill() {
        hideSavedTask?.cancel()
        savingDelayTask?.cancel()
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

enum SettingsSavePillState {
    case saving
    case saved
    case error
}

struct SettingsSaveStatusPill: View {
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
                .appFont(.labelMd)
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
            return "Couldn't save settings"
        }
    }
}

struct SettingsSaveStatusLogic {
    struct Timeline {
        let immediateState: SettingsSavePillState?
    }

    static func timeline(
        wasSaving: Bool,
        isSaving: Bool,
        saveError: String?
    ) -> Timeline {
        let trimmedError = saveError?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedError, !trimmedError.isEmpty {
            return .init(immediateState: .error)
        }
        if isSaving {
            return .init(immediateState: .saving)
        }
        if wasSaving {
            return .init(immediateState: .saved)
        }
        return .init(immediateState: nil)
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
                        .appFont(.subheadline)
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
                .appFont(.subheadline)
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
                .appFont(.headline)
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
