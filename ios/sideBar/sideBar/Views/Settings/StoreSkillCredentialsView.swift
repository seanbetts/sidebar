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
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if showHeader {
                    Text("Credentials")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

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
            .alert(
                "Update API key",
                isPresented: isCredentialEditorPromptPresented,
                presenting: credentialEditorPrompt
            ) { prompt in
                SecureField(
                    "Enter \(providerDisplayName(prompt.provider)) API key",
                    text: $credentialEditorDraft
                )
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
        let impactedSkills: [String]

        var id: String { provider }
    }

    @ViewBuilder
    private func storeProviderCredentialRow(provider: String) -> some View {
        let normalizedProvider = normalizedProviderName(provider)
        let isConnected = providerStatus(for: normalizedProvider)?.hasKey ?? false
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Text(providerDisplayName(normalizedProvider))
                    .font(.caption)
                    .foregroundStyle(.primary)
                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    Text(providerStatusLabel(for: normalizedProvider))
                        .font(.caption2)
                        .foregroundStyle(providerStatusColor(for: normalizedProvider))

                    HStack(spacing: 8) {
                        Button {
                            beginCredentialEditor(provider: normalizedProvider)
                        } label: {
                            Image(systemName: isConnected ? "pencil.circle.fill" : "plus.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                        }
                        .accessibilityLabel(isConnected ? "Update Key" : "Add Key")
                        .frame(width: DesignTokens.Size.touchTarget, height: DesignTokens.Size.touchTarget)
                        .disabled(isProviderActionBusy(normalizedProvider))

                        if isConnected {
                            Button(role: .destructive) {
                                beginCredentialRemoval(provider: normalizedProvider)
                            } label: {
                                Image(systemName: "trash.circle.fill")
                                    .font(.system(size: 18, weight: .semibold))
                            }
                            .accessibilityLabel("Remove Key")
                            .frame(width: DesignTokens.Size.touchTarget, height: DesignTokens.Size.touchTarget)
                            .disabled(isProviderActionBusy(normalizedProvider))
                        }
                    }
                }
            }

            if let providerError = providerKeyErrors[normalizedProvider], !providerError.isEmpty {
                Text(providerError)
                    .font(.caption2)
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
                return "Connected (Key: API key)"
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
            if credentialEditorPrompt?.provider == normalizedProvider {
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
}
