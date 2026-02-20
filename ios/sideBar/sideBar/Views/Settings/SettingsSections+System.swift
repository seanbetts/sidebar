import SwiftUI
import sideBarShared

struct UserSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @EnvironmentObject private var environment: AppEnvironment
    @State private var isPendingWritesPresented = false
    @State private var communicationStyle: String = ""
    @State private var workingRelationship: String = ""
    @State private var hasLoadedDrafts = false
    @State private var isSyncingDrafts = false
    @State private var autosaveTask: Task<Void, Never>?

    private static let systemAutosaveDelayNs: UInt64 = 800_000_000

    var body: some View {
        Form {
            if environment.writeQueue.pendingCount > 0 || environment.writeQueue.isProcessing {
                Section("Sync Status") {
                    HStack(spacing: 8) {
                        SyncStatusIndicator()
                        Text(pendingStatusText)
                            .font(DesignTokens.Typography.labelMd)
                    }
                    Button("View pending changes") {
                        isPendingWritesPresented = true
                    }
                }
            }
            Section {
                TextEditor(text: $communicationStyle)
                .frame(minHeight: 120)
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Communication Style")
                    Text("How the assistant should communicate with you.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                TextEditor(text: $workingRelationship)
                    .frame(minHeight: 120)
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Working Relationship")
                    Text("How you want the assistant to collaborate with you.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let saveError = viewModel.systemSaveError {
                Section {
                    Text(saveError)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.error)
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .sheet(isPresented: $isPendingWritesPresented) {
            NavigationStack {
                PendingWritesView()
            }
            .phoneSheetGrabBarVisible()
        }
        .onAppear {
            syncDraftsFromSettings(viewModel.settings)
        }
        .onChange(of: systemAutosaveSignature) { _, _ in
            scheduleAutosave()
        }
        .onChange(of: settingsSignature) { _, _ in
            syncDraftsFromSettings(viewModel.settings)
        }
        .onDisappear {
            autosaveTask?.cancel()
        }
        .overlay {
            if viewModel.isLoading && viewModel.settings == nil {
                LoadingIndicatorView(size: LoadingIndicatorSize.page)
            }
        }
    }

    private var settingsSignature: String {
        guard let settings = viewModel.settings else {
            return "none"
        }
        return [
            settings.communicationStyle ?? "",
            settings.workingRelationship ?? ""
        ].joined(separator: "|")
    }

    private var systemAutosaveSignature: String {
        [
            communicationStyle,
            workingRelationship
        ].joined(separator: "|")
    }

    private var isDraftDirty: Bool {
        guard let settings = viewModel.settings else { return false }
        return communicationStyle != (settings.communicationStyle ?? "")
            || workingRelationship != (settings.workingRelationship ?? "")
    }

    private func syncDraftsFromSettings(_ settings: UserSettings?) {
        guard let settings else { return }
        if hasLoadedDrafts && isDraftDirty {
            return
        }
        isSyncingDrafts = true
        communicationStyle = settings.communicationStyle ?? ""
        workingRelationship = settings.workingRelationship ?? ""
        hasLoadedDrafts = true
        isSyncingDrafts = false
    }

    private func scheduleAutosave() {
        guard hasLoadedDrafts, !isSyncingDrafts else { return }
        autosaveTask?.cancel()
        guard isDraftDirty else { return }
        autosaveTask = Task {
            try? await Task.sleep(nanoseconds: Self.systemAutosaveDelayNs)
            guard !Task.isCancelled else { return }
            await viewModel.saveUserSettings(
                communicationStyle: communicationStyle,
                workingRelationship: workingRelationship
            )
        }
    }

    private var pendingStatusText: String {
        if environment.writeQueue.isProcessing {
            return "Syncing \(environment.writeQueue.pendingCount) changes"
        }
        return "\(environment.writeQueue.pendingCount) pending changes"
    }
}

struct AgentSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var selectedPrimaryProvider: AIPrimaryProvider = .anthropic
    @State private var providerKeyInput: String = ""

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: $selectedPrimaryProvider) {
                    ForEach(viewModel.supportedPrimaryProviders) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                if selectedProviderHasKey {
                    Text("Key saved (ends in \(selectedProviderKeyLast4 ?? "----"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No API key saved for \(selectedPrimaryProvider.displayName).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                SecureField("Enter \(selectedPrimaryProvider.displayName) API key", text: $providerKeyInput)
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                #endif
                HStack {
                    Button("Save API Key") {
                        Task {
                            let success = await viewModel.savePrimaryProviderKey(
                                provider: selectedPrimaryProvider,
                                apiKey: providerKeyInput
                            )
                            if success {
                                providerKeyInput = ""
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignTokens.Colors.actionPrimary)
                    .disabled(
                        viewModel.isSavingPrimaryProvider
                            || providerKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )

                    if selectedProviderHasKey {
                        Button("Remove Key", role: .destructive) {
                            Task {
                                await viewModel.deletePrimaryProviderKey(provider: selectedPrimaryProvider)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isSavingPrimaryProvider)
                    }
                }
                if let providerError = viewModel.primaryProviderError, !providerError.isEmpty {
                    Text(providerError)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.error)
                }
            } header: {
                sectionHeader(
                    title: "AI Provider",
                    subtitle: "Choose one provider for assistant replies and conversation titles."
                )
            } footer: {
                Text("Strict BYOK mode: add one key for your selected provider.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                readOnlySectionText(resolvedText(viewModel.settings?.assistantIdentity?.name))
            } header: {
                sectionHeader(
                    title: "Assistant Name",
                    subtitle: "Your assistant's name"
                )
            }
            Section {
                readOnlySectionText(resolvedText(viewModel.settings?.assistantIdentity?.tone))
            } header: {
                sectionHeader(
                    title: "Assistant Tone",
                    subtitle: "How \(assistantDisplayName) should sound and respond."
                )
            }
            Section {
                readOnlySectionText(resolvedText(viewModel.settings?.assistantIdentity?.values))
            } header: {
                sectionHeader(
                    title: "Assistant Values",
                    subtitle: "Core principles \(assistantDisplayName) prioritizes."
                )
            }
            Section {
                readOnlySectionText(resolvedText(viewModel.settings?.assistantIdentity?.boundaries))
            } header: {
                sectionHeader(
                    title: "Assistant Boundaries",
                    subtitle: "Limits \(assistantDisplayName) should not cross."
                )
            }
            if let identityMeta = viewModel.settings?.assistantIdentityMeta {
                Section {
                    readOnlySectionText("Updated: \(identityMeta.updatedAt)")
                    readOnlySectionText("Version: \(identityMeta.version)")
                    if let reason = identityMeta.reason, !reason.isEmpty {
                        readOnlySectionText("Reason: \(reason)")
                    }
                } header: {
                    sectionHeader(
                        title: "Assistant Identity Meta",
                        subtitle: "History of identity updates \(assistantDisplayName) has made."
                    )
                }
            }
            Section {
                readOnlySectionText(resolvedText(viewModel.settings?.assistantSoul?.purpose))
            } header: {
                sectionHeader(
                    title: "Soul Purpose",
                    subtitle: "\(assistantPossessiveDisplayName) long-term mission and intent."
                )
            }
            Section {
                readOnlySectionText(resolvedText(viewModel.settings?.assistantSoul?.operatingPrinciples))
            } header: {
                sectionHeader(
                    title: "Soul Operating Principles",
                    subtitle: "Standing rules that guide \(assistantPossessiveDisplayName) day-to-day behavior."
                )
            }
            Section {
                readOnlySectionText(resolvedText(viewModel.settings?.assistantSoul?.adaptationPolicy))
            } header: {
                sectionHeader(
                    title: "Soul Adaptation Policy",
                    subtitle: "How \(assistantDisplayName) should adapt while staying aligned."
                )
            }
            Section {
                readOnlySectionText(resolvedText(viewModel.settings?.assistantSoul?.successSignals))
            } header: {
                sectionHeader(
                    title: "Soul Success Signals",
                    subtitle: "How \(assistantDisplayName) measures good outcomes and alignment."
                )
            } footer: {
                if viewModel.settings?.assistantSoulMeta == nil {
                    agentSettingsFooter
                }
            }
            if let soulMeta = viewModel.settings?.assistantSoulMeta {
                Section {
                    readOnlySectionText("Updated: \(soulMeta.updatedAt)")
                    readOnlySectionText("Version: \(soulMeta.version)")
                    if let reason = soulMeta.reason, !reason.isEmpty {
                        readOnlySectionText("Reason: \(reason)")
                    }
                } header: {
                    sectionHeader(
                        title: "Assistant Soul Meta",
                        subtitle: "History of soul updates \(assistantDisplayName) has made."
                    )
                } footer: {
                    agentSettingsFooter
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .overlay {
            if viewModel.isLoading && viewModel.settings == nil {
                LoadingIndicatorView(size: LoadingIndicatorSize.page)
            }
        }
        .onAppear {
            syncSelectedProvider(from: viewModel.settings)
        }
        .onChange(of: primaryProviderSignature) { _, _ in
            syncSelectedProvider(from: viewModel.settings)
        }
        .onChange(of: selectedPrimaryProvider) { previous, next in
            if previous == next {
                return
            }
            Task {
                await viewModel.savePrimaryProvider(next)
            }
        }
    }

    private func resolvedText(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Not set" : trimmed
    }

    private var assistantDisplayName: String {
        let trimmedName = viewModel.settings?.assistantIdentity?.name?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedName.isEmpty ? "Your assistant" : trimmedName
    }

    private var assistantPossessiveDisplayName: String {
        "\(assistantDisplayName)'s"
    }

    private var primaryProviderSignature: String {
        viewModel.settings?.aiPrimaryProvider ?? ""
    }

    private var selectedProviderHasKey: Bool {
        guard viewModel.settings?.aiPrimaryProvider == selectedPrimaryProvider.rawValue else {
            return false
        }
        return viewModel.settings?.aiPrimaryProviderHasKey ?? false
    }

    private var selectedProviderKeyLast4: String? {
        guard viewModel.settings?.aiPrimaryProvider == selectedPrimaryProvider.rawValue else {
            return nil
        }
        return viewModel.settings?.aiPrimaryProviderKeyLast4
    }

    private func syncSelectedProvider(from settings: UserSettings?) {
        guard let rawProvider = settings?.aiPrimaryProvider,
              let provider = AIPrimaryProvider(rawValue: rawProvider) else {
            return
        }
        selectedPrimaryProvider = provider
    }

    private func readOnlySectionText(_ value: String) -> some View {
        Text(value)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
    }

    @ViewBuilder
    private var agentSettingsFooter: some View {
        Text("Managed by \(assistantDisplayName). User edits are disabled for these fields.")
            .padding(.top, DesignTokens.Spacing.sm)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
