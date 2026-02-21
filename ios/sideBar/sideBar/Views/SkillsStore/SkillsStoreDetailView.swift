import SwiftUI
import sideBarShared

public struct SkillsStoreView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var installInFlight = false
    @State private var installChecksInFlight = false
    @State private var installError: String?
    @State private var storeInstallPrompt: StoreInstallPrompt?
    @State private var providerKeyDrafts: [String: String] = [:]
    @State private var storeInstallPromptError: String?
    @State private var isSubmittingStoreInstallPrompt = false

    public init() {
    }

    public var body: some View {
        Group {
            if let skill = selectedSkill {
                ScrollView {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                        titleCard(skill)
                        installActions(skill)
                        requirementSection(skill)
                    }
                    .frame(maxWidth: 680, alignment: .leading)
                    .padding(DesignTokens.Spacing.lg)
                }
            } else {
                PlaceholderView(
                    title: "Select a skill",
                    subtitle: "Choose a skill from the store list to review requirements and install it.",
                    iconName: "storefront"
                )
            }
        }
        .navigationTitle("Skills Store")
        .sheet(item: $storeInstallPrompt, onDismiss: clearStoreInstallPromptState) { prompt in
            NavigationStack {
                Form {
                    Section {
                        Text(environment.settingsViewModel.displayDescription(for: prompt.skill))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text(environment.settingsViewModel.displayName(for: prompt.skill))
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
    }

    private var selectedSkill: SkillItem? {
        guard let selectedId = environment.skillsStoreSelectedSkillId else { return nil }
        return environment.settingsViewModel.skills.first { $0.id == selectedId && $0.tier == .store }
    }

    private func titleCard(_ skill: SkillItem) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(environment.settingsViewModel.displayName(for: skill))
                .font(DesignTokens.Typography.title2Semibold)
            Text(environment.settingsViewModel.displayDescription(for: skill))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Label(skill.category, systemImage: "tag")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func installActions(_ skill: SkillItem) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            if isInstalled(skill) {
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(DesignTokens.Colors.success)
                if skill.userToggleable {
                    Toggle("Enabled", isOn: Binding(
                        get: { isEnabled(skill.id) },
                        set: { isEnabled in
                            Task {
                                await environment.settingsViewModel.setSkillEnabled(
                                    id: skill.id,
                                    enabled: isEnabled
                                )
                            }
                        }
                    ))
                    .disabled(
                        environment.settingsViewModel.isSavingSkills
                        || environment.settingsViewModel.settings == nil
                    )
                }
            } else if skill.installable {
                Button {
                    Task { await beginStoreInstall(for: skill) }
                } label: {
                    if installInFlight || installChecksInFlight {
                        ProgressView()
                    } else {
                        Text("Install Skill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(installInFlight || installChecksInFlight || environment.settingsViewModel.settings == nil)
            }
            if let installError, !installError.isEmpty {
                Text(installError)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.error)
            }
        }
    }

    private func requirementSection(_ skill: SkillItem) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Requirements")
                .font(DesignTokens.Typography.subheadlineSemibold)
            ForEach(Array(requirementLines(for: skill).enumerated()), id: \.offset) { _, line in
                Label(line, systemImage: "key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func beginStoreInstall(for skill: SkillItem) async {
        guard !installInFlight, !installChecksInFlight else { return }
        installError = nil
        let requiredProviders = requiredProviders(for: skill)
        guard !requiredProviders.isEmpty else {
            _ = await performStoreInstall(skillId: skill.id, providerKeys: [])
            return
        }

        installChecksInFlight = true
        defer { installChecksInFlight = false }

        do {
            var missingProviders: [String] = []
            for provider in requiredProviders {
                let hasKey = try await environment.settingsViewModel.providerHasKey(provider: provider)
                if !hasKey {
                    missingProviders.append(provider)
                }
            }

            if missingProviders.isEmpty {
                _ = await performStoreInstall(skillId: skill.id, providerKeys: [])
                return
            }

            storeInstallPrompt = StoreInstallPrompt(skill: skill, missingProviders: missingProviders)
            providerKeyDrafts = Dictionary(uniqueKeysWithValues: missingProviders.map { ($0, "") })
            storeInstallPromptError = nil
        } catch {
            installError = ErrorMapping.message(for: error)
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

        let succeeded = await performStoreInstall(skillId: prompt.skill.id, providerKeys: providerKeys)
        if succeeded {
            storeInstallPrompt = nil
            clearStoreInstallPromptState()
        } else {
            storeInstallPromptError = installError ?? "Install failed."
        }
    }

    private func performStoreInstall(skillId: String, providerKeys: [StoreSkillProviderKeyInput]) async -> Bool {
        guard !installInFlight else { return false }
        installInFlight = true
        defer { installInFlight = false }
        let succeeded = await environment.settingsViewModel.installStoreSkill(
            id: skillId,
            providerKeys: providerKeys
        )
        if succeeded {
            installError = nil
            return true
        }
        let message = environment.settingsViewModel.skillsError?.trimmingCharacters(in: .whitespacesAndNewlines)
        installError = (message?.isEmpty == false) ? message : "Install failed."
        return false
    }

    private func clearStoreInstallPromptState() {
        providerKeyDrafts = [:]
        storeInstallPromptError = nil
        isSubmittingStoreInstallPrompt = false
    }

    private func requiredProviders(for skill: SkillItem) -> [String] {
        var orderedProviders: [String] = []
        var seen: Set<String> = []
        for requirement in skill.credentialRequirements where requirement.required {
            if requirement.keyKind.lowercased() != "api_key" {
                continue
            }
            let provider = requirement.provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if provider.isEmpty || seen.contains(provider) {
                continue
            }
            orderedProviders.append(provider)
            seen.insert(provider)
        }
        return orderedProviders
    }

    private func requirementLines(for skill: SkillItem) -> [String] {
        if skill.credentialRequirements.isEmpty {
            return ["No API key required"]
        }
        return skill.credentialRequirements.map { requirement in
            let provider = providerDisplayName(requirement.provider)
            if requirement.required {
                return "Requires \(provider) API key"
            }
            if let mode = requirement.mode, !mode.isEmpty {
                return "Optional \(provider) API key (\(mode.replacingOccurrences(of: "_", with: " ")))"
            }
            return "Optional \(provider) API key"
        }
    }

    private func providerDisplayName(_ raw: String) -> String {
        switch raw.lowercased() {
        case "openai":
            return "OpenAI"
        case "anthropic":
            return "Anthropic"
        case "google":
            return "Google"
        default:
            return raw.capitalized
        }
    }

    private func providerKeyBinding(for provider: String) -> Binding<String> {
        Binding(
            get: { providerKeyDrafts[provider] ?? "" },
            set: { providerKeyDrafts[provider] = $0 }
        )
    }

    private func isInstalled(_ skill: SkillItem) -> Bool {
        environment.settingsViewModel.settings?.installedStoreSkills.contains(skill.id) ?? false
    }

    private func isEnabled(_ skillId: String) -> Bool {
        environment.settingsViewModel.settings?.enabledSkills.contains(skillId) ?? false
    }
}

private struct StoreInstallPrompt: Identifiable {
    let skill: SkillItem
    let missingProviders: [String]

    var id: String { skill.id }
}
