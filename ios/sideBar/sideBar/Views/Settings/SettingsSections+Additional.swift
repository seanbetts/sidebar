import Foundation
import SwiftUI
import sideBarShared

// MARK: - Additional Settings Sections

struct SkillsSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var selectedTier: SkillsTierFilter = .standard
    @State private var selectedStoreSkill: SkillItem?

    var body: some View {
        #if os(macOS)
        macSkillsForm
        #else
        iosSkillsForm
        #endif
    }

    #if os(macOS)
    private var macSkillsForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                Picker("Skill Type", selection: $selectedTier) {
                    ForEach(SkillsTierFilter.allCases) { tier in
                        Text(tier.title).tag(tier)
                    }
                }
                .labelsHidden()
                .appFont(.body)
                .pickerStyle(.segmented)
                .frame(maxWidth: .infinity)

                HStack(spacing: DesignTokens.Spacing.md) {
                    Text("Enable all")
                        .appFont(.body)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)

                    Spacer(minLength: DesignTokens.Spacing.md)

                    Toggle("Enable all", isOn: Binding(
                        get: { allSkillsEnabled },
                        set: { isEnabled in
                            handleSetAllSkillsEnabled(isEnabled)
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(
                        viewModel.isSavingSkills
                        || viewModel.isLoadingSkills
                        || viewModel.settings == nil
                        || !hasToggleableSkills
                    )
                }

                if groupedSkills.isEmpty && !viewModel.isLoadingSkills {
                    SettingsMacStatusBanner(message: emptySkillsMessage, tone: .info)
                } else {
                    ForEach(groupedSkills) { section in
                        SettingsMacPanelCard {
                            SettingsMacSectionIntro(
                                title: section.title,
                                message: "Review the skills in this section and decide"
                                    + " which ones should be active for your current workspace."
                            )
                            ForEach(section.skills, id: \.id) { skill in
                                if selectedTier == .store {
                                    storeSkillRow(skill)
                                } else {
                                    skillToggleRow(skill)
                                }
                            }
                        }
                    }
                }
            }
            .padding(DesignTokens.Spacing.lg)
        }
        .background(DesignTokens.Colors.settingsBackground)
        .sheet(item: $selectedStoreSkill) { skill in
            storeSkillDetailSheet(skill)
        }
        .overlay {
            if viewModel.isLoadingSkills && viewModel.skills.isEmpty {
                LoadingIndicatorView(size: LoadingIndicatorSize.page)
            }
        }
    }
    #endif

    private var iosSkillsForm: some View {
        Form {
            Section {
                Picker("Skill Type", selection: $selectedTier) {
                    ForEach(SkillsTierFilter.allCases) { tier in
                        Text(tier.title).tag(tier)
                    }
                }
                .appFont(.body)
                .pickerStyle(.segmented)

                Toggle("Enable all", isOn: Binding(
                    get: { allSkillsEnabled },
                    set: { isEnabled in
                        handleSetAllSkillsEnabled(isEnabled)
                    }
                ))
                .disabled(
                    viewModel.isSavingSkills
                    || viewModel.isLoadingSkills
                    || viewModel.settings == nil
                    || !hasToggleableSkills
                )
            }

            if groupedSkills.isEmpty && !viewModel.isLoadingSkills {
                Section {
                    Text(emptySkillsMessage)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(groupedSkills) { section in
                    Section(section.title) {
                        ForEach(section.skills, id: \.id) { skill in
                            if selectedTier == .store {
                                storeSkillRow(skill)
                            } else {
                                skillToggleRow(skill)
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .contentMargins(.top, DesignTokens.Spacing.xl, for: .scrollContent)
        .background(DesignTokens.Colors.settingsBackground)
        .sheet(item: $selectedStoreSkill) { skill in
            storeSkillDetailSheet(skill)
        }
        .overlay {
            if viewModel.isLoadingSkills && viewModel.skills.isEmpty {
                LoadingIndicatorView(size: LoadingIndicatorSize.page)
            }
        }
    }

    private enum SkillsTierFilter: String, CaseIterable, Identifiable {
        case standard
        case store
        case required

        var id: String { rawValue }

        var title: String {
            switch self {
            case .standard:
                return "Standard"
            case .store:
                return "Store"
            case .required:
                return "Required"
            }
        }
    }

    @ViewBuilder
    private func skillLabel(_ skill: SkillItem) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
            SkillSymbolIcon(
                appIcon: SkillIconResolver.settingsAppIcon(for: skill),
                appFontStyle: .subheading,
                foreground: DesignTokens.Colors.textSecondary
            )
                .frame(width: DesignTokens.Icon.md, height: DesignTokens.Icon.md)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.displayName(for: skill))
                    .appFont(.subheading)

                Text(viewModel.displayDescription(for: skill))
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func skillToggleRow(_ skill: SkillItem) -> some View {
        #if os(macOS)
        SettingsMacSkillRow(
            title: viewModel.displayName(for: skill),
            subtitle: viewModel.displayDescription(for: skill),
            icon: SkillIconResolver.settingsAppIcon(for: skill)
        ) {
            Toggle("", isOn: Binding(
                get: { isSkillEnabled(skill.id) },
                set: { isEnabled in
                    handleSkillToggleChange(id: skill.id, enabled: isEnabled)
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(
                viewModel.isSavingSkills
                || viewModel.settings == nil
                || !skill.userToggleable
            )
        }
        #else
        Toggle(isOn: Binding(
            get: { isSkillEnabled(skill.id) },
            set: { isEnabled in
                handleSkillToggleChange(id: skill.id, enabled: isEnabled)
            }
        )) {
            skillLabel(skill)
        }
        .disabled(
            viewModel.isSavingSkills
            || viewModel.settings == nil
            || !skill.userToggleable
        )
        #endif
    }

    private func storeSkillRow(_ skill: SkillItem) -> some View {
        #if os(macOS)
        SettingsMacSkillRow(
            title: viewModel.displayName(for: skill),
            subtitle: viewModel.displayDescription(for: skill),
            icon: SkillIconResolver.settingsAppIcon(for: skill)
        ) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Button("Details") {
                    selectedStoreSkill = skill
                }
                .buttonStyle(.bordered)

                Toggle("", isOn: Binding(
                    get: { isSkillEnabled(skill.id) },
                    set: { isEnabled in
                        handleSkillToggleChange(id: skill.id, enabled: isEnabled)
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(
                    viewModel.isSavingSkills
                    || viewModel.settings == nil
                    || !skill.userToggleable
                )
            }
        }
        #else
        HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
            Button {
                selectedStoreSkill = skill
            } label: {
                skillLabel(skill)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle("", isOn: Binding(
                get: { isSkillEnabled(skill.id) },
                set: { isEnabled in
                    handleSkillToggleChange(id: skill.id, enabled: isEnabled)
                }
            ))
            .labelsHidden()
            .disabled(
                viewModel.isSavingSkills
                || viewModel.settings == nil
                || !skill.userToggleable
            )
        }
        #endif
    }

    private func storeSkillDetailSheet(_ skill: SkillItem) -> some View {
        StoreSkillDetailSheet(
            viewModel: viewModel,
            skill: skill,
            isStoreActionBusy: viewModel.isSavingSkills,
            isInstalled: isStoreSkillInstalled(skill),
            installError: viewModel.skillsError,
            onInstallTap: {},
            onConfirmUninstall: {
                await uninstallStoreSkillFromSettings(skill)
            }
        )
    }

    private var filteredSkills: [SkillItem] {
        viewModel.skills.filter { skill in
            guard skill.status != "hidden" else {
                return false
            }
            switch selectedTier {
            case .standard:
                return skill.tier == .standard
            case .store:
                return skill.tier == .store && isStoreSkillInstalled(skill)
            case .required:
                return skill.tier == .required
            }
        }
    }

    private var emptySkillsMessage: String {
        switch selectedTier {
        case .store:
            return "No Store skills installed yet. Install skills from the Skills Store to manage them here."
        case .standard, .required:
            return "No skills available."
        }
    }

    private var groupedSkills: [SkillsSettingsSection] {
        SkillsSettingsGrouping.sections(
            from: filteredSkills,
            assistantDisplayName: viewModel.assistantDisplayName,
            displayName: { viewModel.displayName(for: $0) }
        )
    }

    private func handleSkillToggleChange(id: String, enabled: Bool) {
        Haptics.selection()
        Task {
            await viewModel.setSkillEnabled(id: id, enabled: enabled)
        }
    }

    private func handleSetAllSkillsEnabled(_ enabled: Bool) {
        Haptics.selection()
        Task {
            await viewModel.setAllSkillsEnabled(
                enabled,
                scopeSkillIds: enableAllScopeSkillIds
            )
        }
    }

    private func uninstallStoreSkillFromSettings(_ skill: SkillItem) async {
        let didUninstall = await viewModel.uninstallStoreSkill(id: skill.id)
        if didUninstall, selectedStoreSkill?.id == skill.id {
            selectedStoreSkill = nil
        }
    }

    private var enableAllScopeSkillIds: Set<String> {
        Set(
            filteredSkills
                .filter { $0.userToggleable }
                .map(\.id)
        )
    }

    private var allSkillsEnabled: Bool {
        let enabled = Set(viewModel.settings?.enabledSkills ?? [])
        let all = enableAllScopeSkillIds
        // When a tier has no toggleable skills (for example Required),
        // keep the disabled "Enable all" toggle visually on.
        return all.isEmpty || enabled.isSuperset(of: all)
    }

    private var hasToggleableSkills: Bool {
        !enableAllScopeSkillIds.isEmpty
    }

    private func isSkillEnabled(_ id: String) -> Bool {
        viewModel.settings?.enabledSkills.contains(id) ?? false
    }

    private func isStoreSkillInstalled(_ skill: SkillItem) -> Bool {
        viewModel.settings?.installedStoreSkills.contains(skill.id) ?? false
    }
}

private struct SkillsSettingsSection: Identifiable {
    let id: String
    let title: String
    let skills: [SkillItem]
}

private enum SkillsSettingsGrouping {
    static let appSkillIDs: Set<String> = [
        "conversations",
        "files",
        "notes",
        "tasks",
        "web-save"
    ]
    static let agentSkillIDs: Set<String> = [
        "memory",
        "prompt-preview",
        "ui-theme",
        "web-search"
    ]

    static func sections(
        from skills: [SkillItem],
        assistantDisplayName: String,
        displayName: (SkillItem) -> String
    ) -> [SkillsSettingsSection] {
        let orderedSections: [Section] = [.app, .agent(assistantDisplayName), .system]
        let grouped = Dictionary(grouping: skills) { skill in
            section(for: skill, assistantDisplayName: assistantDisplayName)
        }

        return orderedSections.compactMap { section in
            guard let sectionSkills = grouped[section], !sectionSkills.isEmpty else {
                return nil
            }
            return SkillsSettingsSection(
                id: section.id,
                title: section.title,
                skills: sectionSkills.sorted {
                    displayName($0).localizedCaseInsensitiveCompare(displayName($1))
                        == .orderedAscending
                }
            )
        }
    }

    private static func section(
        for skill: SkillItem,
        assistantDisplayName: String
    ) -> Section {
        if appSkillIDs.contains(skill.id) {
            return .app
        }
        if agentSkillIDs.contains(skill.id) {
            return .agent(assistantDisplayName)
        }
        return .system
    }

    private enum Section: Hashable {
        case app
        case agent(String)
        case system

        var id: String {
            switch self {
            case .app:
                return "app"
            case .agent:
                return "agent"
            case .system:
                return "system"
            }
        }

        var title: String {
            switch self {
            case .app:
                return "App"
            case let .agent(assistantDisplayName):
                return assistantDisplayName
            case .system:
                return "System"
            }
        }
    }
}
