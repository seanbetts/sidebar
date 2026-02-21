import SwiftUI
import sideBarShared

struct StoreSkillCredentialsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    let skill: SkillItem

    @State private var providerKeyStatuses: [String: ProviderKeyStatusResponse] = [:]
    @State private var providerKeyStatusInFlight: Set<String> = []
    @State private var providerKeyMutationInFlight: Set<String> = []
    @State private var providerKeyErrors: [String: String] = [:]
    @State private var activeCredentialEditor: CredentialEditorPrompt?
    @State private var credentialEditorDraft: String = ""
    @State private var credentialEditorError: String?
    @State private var removeCredentialPrompt: RemoveCredentialPrompt?

    var body: some View {
        if providers.isEmpty {
            Text("No provider API keys required.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Credentials")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(Array(providers.enumerated()), id: \.offset) { index, provider in
                    storeProviderCredentialRow(provider: provider)
                    if index < providers.count - 1 {
                        Divider()
                    }
                }
            }
            .alert(item: $removeCredentialPrompt) { prompt in
                Alert(
                    title: Text("Remove \(providerDisplayName(prompt.provider)) API key?"),
                    message: Text(removeCredentialPromptMessage(prompt)),
                    primaryButton: .destructive(Text("Remove Key")) {
                        Task {
                            await confirmCredentialRemoval(prompt)
                        }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    private struct CredentialEditorPrompt: Identifiable {
        let provider: String

        var id: String { provider }
    }

    private struct RemoveCredentialPrompt: Identifiable {
        let provider: String
        let impactedSkills: [String]

        var id: String { provider }
    }

    @ViewBuilder
    private func storeProviderCredentialRow(provider: String) -> some View {
        let normalizedProvider = normalizedProviderName(provider)
        let isConnected = providerStatus(for: normalizedProvider)?.hasKey ?? false
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(providerDisplayName(normalizedProvider))
                    .font(.caption)
                    .foregroundStyle(.primary)
                Spacer()
                Text(providerStatusLabel(for: normalizedProvider))
                    .font(.caption2)
                    .foregroundStyle(providerStatusColor(for: normalizedProvider))
            }

            HStack(spacing: 12) {
                Button(isConnected ? "Update Key" : "Add Key") {
                    beginCredentialEditor(provider: normalizedProvider)
                }
                .font(.caption)
                .disabled(isProviderActionBusy(normalizedProvider))

                if isConnected {
                    Button("Remove Key", role: .destructive) {
                        beginCredentialRemoval(provider: normalizedProvider)
                    }
                    .font(.caption)
                    .disabled(isProviderActionBusy(normalizedProvider))
                }
            }

            if let providerError = providerKeyErrors[normalizedProvider], !providerError.isEmpty {
                Text(providerError)
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.Colors.error)
            }

            if isCredentialEditorActive(provider: normalizedProvider) {
                credentialEditor(for: normalizedProvider)
            }
        }
        .task(id: normalizedProvider) {
            await loadProviderStatusIfNeeded(provider: normalizedProvider)
        }
    }

    @ViewBuilder
    private func credentialEditor(for provider: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SecureField(
                "Enter \(providerDisplayName(provider)) API key",
                text: $credentialEditorDraft
            )
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            #endif

            if let credentialEditorError, !credentialEditorError.isEmpty {
                Text(credentialEditorError)
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.Colors.error)
            }

            HStack(spacing: 12) {
                Button("Save Key") {
                    Task {
                        await submitCredentialEditor(provider: provider)
                    }
                }
                .font(.caption)
                .disabled(
                    providerKeyMutationInFlight.contains(provider)
                        || credentialEditorDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )

                Button("Cancel", role: .cancel) {
                    clearCredentialEditor()
                }
                .font(.caption)
                .disabled(providerKeyMutationInFlight.contains(provider))
            }
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
                    return "Connected (\(keyLast4))"
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
        activeCredentialEditor = CredentialEditorPrompt(provider: normalizedProviderName(provider))
        credentialEditorDraft = ""
        credentialEditorError = nil
    }

    private func isCredentialEditorActive(provider: String) -> Bool {
        activeCredentialEditor?.provider == normalizedProviderName(provider)
    }

    private func clearCredentialEditor() {
        activeCredentialEditor = nil
        credentialEditorDraft = ""
        credentialEditorError = nil
    }

    private func submitCredentialEditor(provider: String) async {
        let normalizedProvider = normalizedProviderName(provider)
        guard activeCredentialEditor?.provider == normalizedProvider else { return }
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
            impactedSkills: impactedInstalledSkillNames(for: normalizedProvider)
        )
    }

    private func confirmCredentialRemoval(_ prompt: RemoveCredentialPrompt) async {
        let normalizedProvider = normalizedProviderName(prompt.provider)
        guard !providerKeyMutationInFlight.contains(normalizedProvider) else { return }

        providerKeyMutationInFlight.insert(normalizedProvider)
        defer { providerKeyMutationInFlight.remove(normalizedProvider) }

        do {
            let status = try await viewModel.deleteProviderKey(provider: normalizedProvider)
            providerKeyStatuses[normalizedProvider] = status
            providerKeyErrors[normalizedProvider] = nil
            if activeCredentialEditor?.provider == normalizedProvider {
                clearCredentialEditor()
            }
        } catch {
            providerKeyErrors[normalizedProvider] = ErrorMapping.message(for: error)
        }
    }

    private func removeCredentialPromptMessage(_ prompt: RemoveCredentialPrompt) -> String {
        guard !prompt.impactedSkills.isEmpty else {
            return "Removing this key may block any installed store skill that requires this provider."
        }
        let previewCount = min(prompt.impactedSkills.count, 3)
        let previewList = prompt.impactedSkills.prefix(previewCount).joined(separator: ", ")
        if prompt.impactedSkills.count > previewCount {
            let remainder = prompt.impactedSkills.count - previewCount
            return "This will affect \(previewList), and \(remainder) more installed skill(s)."
        }
        return "This will affect \(previewList)."
    }

    private func impactedInstalledSkillNames(for provider: String) -> [String] {
        let installedStoreSkillIds = Set(viewModel.settings?.installedStoreSkills ?? [])
        return SkillsStoreLogic.installedStoreSkillsRequiringProvider(
            provider,
            skills: viewModel.skills,
            installedStoreSkillIds: installedStoreSkillIds
        )
            .map { viewModel.displayName(for: $0) }
            .sorted()
    }

    private func providerDisplayName(_ raw: String) -> String {
        SkillsStoreLogic.providerDisplayName(raw)
    }
}
