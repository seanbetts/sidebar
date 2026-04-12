import SwiftUI
import sideBarShared

struct StoreSkillCredentialsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    let skill: SkillItem
    let showHeader: Bool
    let showEmptyState: Bool

    @State private var providerKeyStatuses: [String: ProviderKeyStatusResponse] = [:]
    @State private var providerKeyStatusInFlight: Set<String> = []
    @State private var providerKeyMutationInFlight: Set<String> = []
    @State private var providerKeyErrors: [String: String] = [:]
    @State private var credentialEditorPrompt: CredentialEditorPrompt?
    @State private var credentialEditorDraft: String = ""
    @State private var credentialEditorError: String?
    @State private var removeCredentialPrompt: RemoveCredentialPrompt?

    init(
        viewModel: SettingsViewModel,
        skill: SkillItem,
        showHeader: Bool = true,
        showEmptyState: Bool = true
    ) {
        self.viewModel = viewModel
        self.skill = skill
        self.showHeader = showHeader
        self.showEmptyState = showEmptyState
    }

    var body: some View {
        if providers.isEmpty {
            if showEmptyState {
                Text("No provider API keys required.")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                if showHeader {
                    Text("Credentials")
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(Array(providers.enumerated()), id: \.offset) { index, provider in
                    #if os(macOS)
                    macStoreProviderCredentialRow(provider: provider)
                    #else
                    storeProviderCredentialRow(provider: provider)
                    #endif
                    if index < providers.count - 1 {
                        Divider()
                    }
                }
            }
            .destructiveConfirmationAlert(
                title: removeCredentialPromptTitle,
                isPresented: isRemoveCredentialPromptPresented,
                message: removeCredentialPromptMessage,
                confirmTitle: "Turn Off",
                onConfirm: {
                    guard let prompt = removeCredentialPrompt else { return }
                    removeCredentialPrompt = nil
                    Task {
                        await confirmCredentialRemoval(prompt)
                    }
                },
                onCancel: {
                    removeCredentialPrompt = nil
                }
            )
            .alert(
                "Update API key",
                isPresented: isCredentialEditorPromptPresented,
                presenting: credentialEditorPrompt
            ) { prompt in
                SecureField(
                    "Enter \(providerDisplayName(prompt.provider)) API key",
                    text: $credentialEditorDraft
                )
                .sidebarTextEntryField()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                #endif
                Button("Save Key") {
                    Task {
                        await submitCredentialEditor(provider: prompt.provider)
                    }
                }
                .disabled(providerKeyMutationInFlight.contains(prompt.provider))
                Button("Cancel", role: .cancel) {
                    clearCredentialEditor()
                }
            } message: { prompt in
                if let credentialEditorError, !credentialEditorError.isEmpty {
                    Text("\(providerDisplayName(prompt.provider)) key update failed: \(credentialEditorError)")
                } else {
                    Text("Enter a new API key for \(providerDisplayName(prompt.provider)).")
                }
            }
        }
    }

    private struct CredentialEditorPrompt: Identifiable {
        let provider: String

        var id: String { provider }
    }

    private struct RemoveCredentialPrompt: Identifiable {
        let provider: String
        let otherImpactedSkills: [String]

        var id: String { provider }
    }

    #if os(macOS)
    @ViewBuilder
    private func macStoreProviderCredentialRow(provider: String) -> some View {
        let normalizedProvider = normalizedProviderName(provider)
        let isConnected = providerStatus(for: normalizedProvider)?.hasKey ?? false

        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            SettingsMacSkillRow(
                title: providerDisplayName(normalizedProvider),
                subtitle: providerStatusLabel(for: normalizedProvider),
                systemImage: isConnected ? "key.fill" : "key"
            ) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Button {
                        beginCredentialEditor(provider: normalizedProvider)
                    } label: {
                        Image(systemName: isConnected ? "pencil.circle.fill" : "plus.circle.fill")
                            .appFont(.size18Semibold)
                    }
                    .accessibilityLabel(isConnected ? "Update Key" : "Add Key")
                    .disabled(isProviderActionBusy(normalizedProvider))
                    .buttonStyle(.plain)

                    if isConnected {
                        Button(role: .destructive) {
                            beginCredentialRemoval(provider: normalizedProvider)
                        } label: {
                            Image(systemName: "trash.circle.fill")
                                .appFont(.size18Semibold)
                        }
                        .accessibilityLabel("Turn Off Skill")
                        .disabled(isProviderActionBusy(normalizedProvider))
                        .buttonStyle(.plain)
                    }
                }
            }
            .task(id: normalizedProvider) {
                await loadProviderStatusIfNeeded(provider: normalizedProvider)
            }

            if let providerError = providerKeyErrors[normalizedProvider], !providerError.isEmpty {
                SettingsMacStatusBanner(message: providerError, tone: .error)
            }
        }
    }
    #endif

    @ViewBuilder
    private func storeProviderCredentialRow(provider: String) -> some View {
        let normalizedProvider = normalizedProviderName(provider)
        let isConnected = providerStatus(for: normalizedProvider)?.hasKey ?? false
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 6) {
                Text(providerDisplayName(normalizedProvider))
                    .appFont(.caption)
                    .foregroundStyle(.primary)
                Spacer()

                HStack(spacing: 0) {
                    Text(providerStatusLabel(for: normalizedProvider))
                        .appFont(.caption2)
                        .foregroundStyle(providerStatusColor(for: normalizedProvider))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Button {
                        beginCredentialEditor(provider: normalizedProvider)
                    } label: {
                        Image(systemName: isConnected ? "pencil.circle.fill" : "plus.circle.fill")
                            .appFont(.size18Semibold)
                    }
                    .accessibilityLabel(isConnected ? "Update Key" : "Add Key")
                    .frame(width: 30, height: 30)
                    .disabled(isProviderActionBusy(normalizedProvider))
                    .buttonStyle(.plain)

                    if isConnected {
                        Button(role: .destructive) {
                            beginCredentialRemoval(provider: normalizedProvider)
                        } label: {
                            Image(systemName: "trash.circle.fill")
                                .appFont(.size18Semibold)
                        }
                        .accessibilityLabel("Turn Off Skill")
                        .frame(width: 30, height: 30)
                        .disabled(isProviderActionBusy(normalizedProvider))
                        .buttonStyle(.plain)
                    }
                }
            }

            if let providerError = providerKeyErrors[normalizedProvider], !providerError.isEmpty {
                Text(providerError)
                    .appFont(.caption2)
                    .foregroundStyle(DesignTokens.Colors.error)
            }
        }
        .task(id: normalizedProvider) {
            await loadProviderStatusIfNeeded(provider: normalizedProvider)
        }
    }

    private var providers: [String] {
        SkillsStoreLogic.requiredProviders(for: skill)
    }

    private func normalizedProviderName(_ provider: String) -> String {
        provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func providerStatus(for provider: String) -> ProviderKeyStatusResponse? {
        providerKeyStatuses[normalizedProviderName(provider)]
    }

    private func providerStatusLabel(for provider: String) -> String {
        let normalizedProvider = normalizedProviderName(provider)
        if providerKeyStatusInFlight.contains(normalizedProvider) {
            return "Checking..."
        }
        if let status = providerStatus(for: normalizedProvider) {
            if status.hasKey {
                if let keyLast4 = status.keyLast4, !keyLast4.isEmpty {
                    return "Connected (****\(keyLast4))"
                }
                return "Connected"
            }
            return "Missing"
        }
        if providerKeyErrors[normalizedProvider] != nil {
            return "Unavailable"
        }
        return "Checking..."
    }

    private func providerStatusColor(for provider: String) -> Color {
        let normalizedProvider = normalizedProviderName(provider)
        if providerKeyStatusInFlight.contains(normalizedProvider) {
            return .secondary
        }
        if let status = providerStatus(for: normalizedProvider) {
            return status.hasKey ? DesignTokens.Colors.success : DesignTokens.Colors.error
        }
        if providerKeyErrors[normalizedProvider] != nil {
            return DesignTokens.Colors.error
        }
        return .secondary
    }

    private func isProviderActionBusy(_ provider: String) -> Bool {
        let normalizedProvider = normalizedProviderName(provider)
        return providerKeyStatusInFlight.contains(normalizedProvider)
            || providerKeyMutationInFlight.contains(normalizedProvider)
    }

    private func loadProviderStatusIfNeeded(provider: String) async {
        let normalizedProvider = normalizedProviderName(provider)
        if normalizedProvider.isEmpty
            || providerKeyStatuses[normalizedProvider] != nil
            || providerKeyStatusInFlight.contains(normalizedProvider) {
            return
        }
        await refreshProviderStatus(provider: normalizedProvider)
    }

    private func refreshProviderStatus(provider: String) async {
        let normalizedProvider = normalizedProviderName(provider)
        guard !normalizedProvider.isEmpty else { return }
        guard !providerKeyStatusInFlight.contains(normalizedProvider) else { return }
        providerKeyStatusInFlight.insert(normalizedProvider)
        defer { providerKeyStatusInFlight.remove(normalizedProvider) }

        do {
            let status = try await viewModel.providerKeyStatus(provider: normalizedProvider)
            providerKeyStatuses[normalizedProvider] = status
            providerKeyErrors[normalizedProvider] = nil
        } catch {
            providerKeyErrors[normalizedProvider] = ErrorMapping.message(for: error)
        }
    }

    private func beginCredentialEditor(provider: String) {
        credentialEditorPrompt = CredentialEditorPrompt(provider: normalizedProviderName(provider))
        credentialEditorDraft = ""
        credentialEditorError = nil
    }

    private func clearCredentialEditor() {
        credentialEditorPrompt = nil
        credentialEditorDraft = ""
        credentialEditorError = nil
    }

    private func submitCredentialEditor(provider: String) async {
        let normalizedProvider = normalizedProviderName(provider)
        guard credentialEditorPrompt?.provider == normalizedProvider else { return }
        let trimmedKey = credentialEditorDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            credentialEditorError = "API key is required."
            return
        }
        guard !providerKeyMutationInFlight.contains(normalizedProvider) else { return }

        providerKeyMutationInFlight.insert(normalizedProvider)
        defer { providerKeyMutationInFlight.remove(normalizedProvider) }

        do {
            let status = try await viewModel.saveProviderKey(
                provider: normalizedProvider,
                apiKey: trimmedKey
            )
            providerKeyStatuses[normalizedProvider] = status
            providerKeyErrors[normalizedProvider] = nil
            Haptics.selection()
            clearCredentialEditor()
        } catch {
            let message = ErrorMapping.message(for: error)
            credentialEditorError = message
            providerKeyErrors[normalizedProvider] = message
        }
    }

    private func beginCredentialRemoval(provider: String) {
        let normalizedProvider = normalizedProviderName(provider)
        removeCredentialPrompt = RemoveCredentialPrompt(
            provider: normalizedProvider,
            otherImpactedSkills: otherInstalledSkillNamesRequiringProvider(for: normalizedProvider)
        )
    }

    private func confirmCredentialRemoval(_ prompt: RemoveCredentialPrompt) async {
        let normalizedProvider = normalizedProviderName(prompt.provider)
        guard !providerKeyMutationInFlight.contains(normalizedProvider) else { return }

        providerKeyMutationInFlight.insert(normalizedProvider)
        defer { providerKeyMutationInFlight.remove(normalizedProvider) }

        do {
            _ = try await viewModel.disconnectProviderConsumer(
                provider: normalizedProvider,
                source: .skill,
                skillId: skill.id
            )
            await refreshProviderStatus(provider: normalizedProvider)
            providerKeyErrors[normalizedProvider] = nil
            if credentialEditorPrompt?.provider == normalizedProvider {
                clearCredentialEditor()
            }
        } catch {
            providerKeyErrors[normalizedProvider] = ErrorMapping.message(for: error)
        }
    }

    private func removeCredentialPromptMessage(_ prompt: RemoveCredentialPrompt) -> String {
        let skillName = viewModel.displayName(for: skill)
        let providerName = providerDisplayName(prompt.provider)
        guard !prompt.otherImpactedSkills.isEmpty else {
            return "This turns off \(skillName). If no other active consumers remain, your \(providerName) key is removed."
        }
        let previewCount = min(prompt.otherImpactedSkills.count, 3)
        let previewList = prompt.otherImpactedSkills.prefix(previewCount).joined(separator: ", ")
        if prompt.otherImpactedSkills.count > previewCount {
            let remainder = prompt.otherImpactedSkills.count - previewCount
            return "This turns off \(skillName). Your \(providerName) key stays connected for \(previewList), "
                + "and \(remainder) more skill(s)."
        }
        return "This turns off \(skillName). Your \(providerName) key stays connected for \(previewList)."
    }

    private var removeCredentialPromptTitle: String {
        "Turn off \(viewModel.displayName(for: skill))?"
    }

    private var removeCredentialPromptMessage: String {
        guard let prompt = removeCredentialPrompt else {
            return ""
        }
        return removeCredentialPromptMessage(prompt)
    }

    private func otherInstalledSkillNamesRequiringProvider(for provider: String) -> [String] {
        let installedStoreSkillIds = Set(viewModel.settings?.installedStoreSkills ?? [])
        return SkillsStoreLogic.installedStoreSkillsRequiringProvider(
            provider,
            skills: viewModel.skills,
            installedStoreSkillIds: installedStoreSkillIds
        )
            .filter { $0.id != skill.id }
            .map { viewModel.displayName(for: $0) }
            .sorted()
    }

    private func providerDisplayName(_ raw: String) -> String {
        SkillsStoreLogic.providerDisplayName(raw)
    }

    private var isCredentialEditorPromptPresented: Binding<Bool> {
        Binding(
            get: { credentialEditorPrompt != nil },
            set: { isPresented in
                if !isPresented {
                    clearCredentialEditor()
                }
            }
        )
    }

    private var isRemoveCredentialPromptPresented: Binding<Bool> {
        Binding(
            get: { removeCredentialPrompt != nil },
            set: { isPresented in
                if !isPresented {
                    removeCredentialPrompt = nil
                }
            }
        )
    }
}
