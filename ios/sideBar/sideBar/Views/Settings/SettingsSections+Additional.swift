import SwiftUI
import sideBarShared

// MARK: - Additional Settings Sections

struct SkillsSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var selectedTier: SkillsTierFilter = .standard
    @State private var installInFlight: Set<String> = []
    @State private var installChecksInFlight: Set<String> = []
    @State private var installErrors: [String: String] = [:]
    @State private var storeInstallPrompt: StoreInstallPrompt?
    @State private var providerKeyDrafts: [String: String] = [:]
    @State private var storeInstallPromptError: String?
    @State private var isSubmittingStoreInstallPrompt = false

    var body: some View {
        Form {
            Section {
                Picker("Skill Type", selection: $selectedTier) {
                    ForEach(SkillsTierFilter.allCases) { tier in
                        Text(tier.title).tag(tier)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Enable all", isOn: Binding(
                    get: { allSkillsEnabled },
                    set: { isEnabled in
                        Task { await viewModel.setAllSkillsEnabled(isEnabled, scopeSkillIds: enableAllScopeSkillIds) }
                    }
                ))
                .disabled(
                    viewModel.isSavingSkills ||
                    viewModel.isLoadingSkills ||
                    viewModel.settings == nil ||
                    !hasToggleableSkills
                )
            }
            if let error = viewModel.skillsError {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.error)
                }
            }
            if groupedSkills.isEmpty && !viewModel.isLoadingSkills {
                Section {
                    Text("No skills available.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(groupedSkills, id: \.0) { category, skills in
                    Section(category) {
                        ForEach(skills, id: \.id) { skill in
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle(isOn: Binding(
                                    get: { isSkillEnabled(skill.id) },
                                    set: { isEnabled in
                                        Task { await viewModel.setSkillEnabled(id: skill.id, enabled: isEnabled) }
                                    }
                                )) {
                                    skillLabel(skill)
                                }
                                .disabled(
                                    viewModel.isSavingSkills ||
                                    viewModel.settings == nil ||
                                    !skill.userToggleable ||
                                    (selectedTier == .store && !isStoreSkillInstalled(skill))
                                )

                                if selectedTier == .store {
                                    storeRequirementLines(skill)
                                    storeInstallButton(skill)
                                    storeCredentialsControls(skill)
                                    if let installError = installErrors[skill.id], !installError.isEmpty {
                                        Text(installError)
                                            .font(.caption)
                                            .foregroundStyle(DesignTokens.Colors.error)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .sheet(item: $storeInstallPrompt, onDismiss: clearStoreInstallPromptState) { prompt in
            NavigationStack {
                Form {
                    Section {
                        Text(viewModel.displayDescription(for: prompt.skill))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text(viewModel.displayName(for: prompt.skill))
                    }

                    Section("Required Provider Keys") {
                        ForEach(prompt.missingProviders, id: \.self) { provider in
                            SecureField(
                                "\(providerDisplayName(provider)) API key",
                                text: providerKeyBinding(for: provider)
                            )
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            #endif
                        }
                        if let storeInstallPromptError, !storeInstallPromptError.isEmpty {
                            Text(storeInstallPromptError)
                                .font(.caption)
                                .foregroundStyle(DesignTokens.Colors.error)
                        }
                    }

                    Section {
                        Button {
                            Task {
                                await submitStoreInstallPrompt(prompt)
                            }
                        } label: {
                            if isSubmittingStoreInstallPrompt {
                                ProgressView()
                            } else {
                                Text("Install Skill")
                            }
                        }
                        .disabled(isSubmittingStoreInstallPrompt)
                    } footer: {
                        Text("Keys are saved for future installs and reused automatically.")
                    }
                }
                .navigationTitle("Install Skill")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            storeInstallPrompt = nil
                        }
                    }
                }
            }
            .phoneSheetGrabBarVisible()
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

    private struct StoreInstallPrompt: Identifiable {
        let skill: SkillItem
        let missingProviders: [String]

        var id: String { skill.id }
    }

    @ViewBuilder
    private func skillLabel(_ skill: SkillItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(viewModel.displayName(for: skill))
                    .font(DesignTokens.Typography.subheadlineSemibold)

                if selectedTier == .store && isStoreSkillInstalled(skill) {
                    Text("Installed")
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(DesignTokens.Colors.success.opacity(0.18)))
                        .foregroundStyle(DesignTokens.Colors.success)
                }

                if !skill.userToggleable && skill.showRequiredBadge {
                    Text("Required")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
            }

            Text(viewModel.displayDescription(for: skill))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func storeRequirementLines(_ skill: SkillItem) -> some View {
        ForEach(Array(requirementLines(for: skill).enumerated()), id: \.offset) { _, line in
            Label(line, systemImage: "key")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func storeInstallButton(_ skill: SkillItem) -> some View {
        if skill.installable && !isStoreSkillInstalled(skill) {
            Button {
                Task {
                    await beginStoreInstall(for: skill)
                }
            } label: {
                if isStoreInstallBusy(skill.id) {
                    ProgressView()
                } else {
                    Text("Install")
                }
            }
            .disabled(
                isStoreInstallBusy(skill.id) ||
                viewModel.isSavingSkills ||
                viewModel.settings == nil
            )
        }
    }

    @ViewBuilder
    private func storeCredentialsControls(_ skill: SkillItem) -> some View {
        if isStoreSkillInstalled(skill) {
            StoreSkillCredentialsView(
                viewModel: viewModel,
                skill: skill
            )
        }
    }

    private func beginStoreInstall(for skill: SkillItem) async {
        guard !isStoreInstallBusy(skill.id) else { return }
        installErrors[skill.id] = nil
        let requiredProviders = requiredProviders(for: skill)
        guard !requiredProviders.isEmpty else {
            _ = await performStoreInstall(skillId: skill.id, providerKeys: [])
            return
        }

        installChecksInFlight.insert(skill.id)
        defer { installChecksInFlight.remove(skill.id) }

        do {
            var missingProviders: [String] = []
            for provider in requiredProviders {
                let hasKey = try await viewModel.providerHasKey(provider: provider)
                if !hasKey {
                    missingProviders.append(provider)
                }
            }

            if missingProviders.isEmpty {
                _ = await performStoreInstall(skillId: skill.id, providerKeys: [])
                return
            }

            storeInstallPrompt = StoreInstallPrompt(skill: skill, missingProviders: missingProviders)
            providerKeyDrafts = Dictionary(
                uniqueKeysWithValues: missingProviders.map { ($0, "") }
            )
            storeInstallPromptError = nil
        } catch {
            installErrors[skill.id] = ErrorMapping.message(for: error)
        }
    }

    private func submitStoreInstallPrompt(_ prompt: StoreInstallPrompt) async {
        storeInstallPromptError = nil
        let providerKeys = prompt.missingProviders.compactMap { provider -> StoreSkillProviderKeyInput? in
            let key = providerKeyDrafts[provider]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !key.isEmpty else { return nil }
            return StoreSkillProviderKeyInput(provider: provider, apiKey: key)
        }
        guard providerKeys.count == prompt.missingProviders.count else {
            storeInstallPromptError = "All required provider keys must be entered."
            return
        }

        isSubmittingStoreInstallPrompt = true
        defer { isSubmittingStoreInstallPrompt = false }

        let succeeded = await performStoreInstall(
            skillId: prompt.skill.id,
            providerKeys: providerKeys
        )
        if succeeded {
            storeInstallPrompt = nil
            clearStoreInstallPromptState()
        } else {
            storeInstallPromptError = installErrors[prompt.skill.id] ?? "Install failed."
        }
    }

    private func performStoreInstall(
        skillId: String,
        providerKeys: [StoreSkillProviderKeyInput]
    ) async -> Bool {
        guard !installInFlight.contains(skillId) else { return false }
        installInFlight.insert(skillId)
        defer { installInFlight.remove(skillId) }
        let succeeded = await viewModel.installStoreSkill(
            id: skillId,
            providerKeys: providerKeys
        )
        if succeeded {
            installErrors[skillId] = nil
            return true
        }
        let message = viewModel.skillsError?.trimmingCharacters(in: .whitespacesAndNewlines)
        installErrors[skillId] = (message?.isEmpty == false) ? message : "Install failed."
        return false
    }

    private func clearStoreInstallPromptState() {
        providerKeyDrafts = [:]
        storeInstallPromptError = nil
        isSubmittingStoreInstallPrompt = false
    }

    private func providerKeyBinding(for provider: String) -> Binding<String> {
        Binding(
            get: { providerKeyDrafts[provider] ?? "" },
            set: { providerKeyDrafts[provider] = $0 }
        )
    }

    private func isStoreInstallBusy(_ skillId: String) -> Bool {
        installInFlight.contains(skillId) || installChecksInFlight.contains(skillId)
    }

    private func requiredProviders(for skill: SkillItem) -> [String] {
        SkillsStoreLogic.requiredProviders(for: skill)
    }

    private func requirementLines(for skill: SkillItem) -> [String] {
        SkillsStoreLogic.requirementLines(for: skill)
    }

    private func providerDisplayName(_ raw: String) -> String {
        SkillsStoreLogic.providerDisplayName(raw)
    }

    private var filteredSkills: [SkillItem] {
        viewModel.skills.filter { skill in
            switch selectedTier {
            case .standard:
                return skill.tier == .standard
            case .store:
                return skill.tier == .store && skill.status != "hidden"
            case .required:
                return skill.tier == .required
            }
        }
    }

    private var groupedSkills: [(String, [SkillItem])] {
        let grouped = Dictionary(grouping: filteredSkills) { $0.category }
        return grouped.keys.sorted().map { key in
            (key, grouped[key]?.sorted { $0.name < $1.name } ?? [])
        }
    }

    private var enableAllScopeSkillIds: Set<String> {
        Set(
            filteredSkills
                .filter { $0.userToggleable }
                .filter { selectedTier != .store || isStoreSkillInstalled($0) }
                .map(\.id)
        )
    }

    private var allSkillsEnabled: Bool {
        let enabled = Set(viewModel.settings?.enabledSkills ?? [])
        let all = enableAllScopeSkillIds
        return !all.isEmpty && enabled.isSuperset(of: all)
    }

    private var hasToggleableSkills: Bool {
        !enableAllScopeSkillIds.isEmpty
    }

    private func isSkillEnabled(_ id: String) -> Bool {
        viewModel.settings?.enabledSkills.contains(id) ?? false
    }

    private func isStoreSkillInstalled(_ skill: SkillItem) -> Bool {
        guard skill.installable else { return true }
        return viewModel.settings?.installedStoreSkills.contains(skill.id) ?? false
    }
}
