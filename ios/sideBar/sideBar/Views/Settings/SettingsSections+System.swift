import SwiftUI
import sideBarShared

struct UserSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @EnvironmentObject var environment: AppEnvironment
    @State var isPendingWritesPresented = false
    @State var communicationStyle: String = ""
    @State var workingRelationship: String = ""
    @State var hasLoadedDrafts = false
    @State var isSyncingDrafts = false
    @State var draftsUserId: String?
    @State var autosaveTask: Task<Void, Never>?

    private static let systemAutosaveDelayNs: UInt64 = 800_000_000

    var body: some View {
        #if os(macOS)
        macUserSettingsBody
        #else
        Form {
            if environment.writeQueue.pendingCount > 0 || environment.writeQueue.isProcessing {
                Section("Sync Status") {
                    HStack(spacing: 8) {
                        SyncStatusIndicator()
                        Text(pendingStatusText)
                            .appFont(.labelMd)
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
                        .appFont(.caption)
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
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let saveError = viewModel.systemSaveError {
                Section {
                    Text(saveError)
                        .appFont(.caption)
                        .foregroundStyle(DesignTokens.Colors.error)
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .sheet(isPresented: $isPendingWritesPresented) {
            MacModalShell(type: pendingWritesPanelType()) {
                NavigationStack {
                    PendingWritesView()
                }
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
        #endif
    }

    var settingsSignature: String {
        guard let settings = viewModel.settings else {
            return "none"
        }
        return [
            settings.userId,
            settings.communicationStyle ?? "",
            settings.workingRelationship ?? ""
        ].compactMap { $0 }.joined(separator: "|")
    }

    var systemAutosaveSignature: String {
        [
            communicationStyle,
            workingRelationship
        ].joined(separator: "|")
    }

    var isDraftDirty: Bool {
        guard let settings = viewModel.settings else { return false }
        return communicationStyle != (settings.communicationStyle ?? "")
            || workingRelationship != (settings.workingRelationship ?? "")
    }

    func syncDraftsFromSettings(_ settings: UserSettings?) {
        guard let settings else { return }
        let shouldSync = SettingsDraftSynchronizer.shouldSyncDrafts(
            hasLoadedDrafts: hasLoadedDrafts,
            isDraftDirty: isDraftDirty,
            previousUserId: draftsUserId,
            nextUserId: settings.userId
        )
        if !shouldSync {
            return
        }
        if SettingsDraftSynchronizer.normalizedUserId(draftsUserId) != SettingsDraftSynchronizer.normalizedUserId(settings.userId) {
            autosaveTask?.cancel()
        }
        isSyncingDrafts = true
        communicationStyle = settings.communicationStyle ?? ""
        workingRelationship = settings.workingRelationship ?? ""
        draftsUserId = settings.userId
        hasLoadedDrafts = true
        isSyncingDrafts = false
    }

    func scheduleAutosave() {
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

    var pendingStatusText: String {
        if environment.writeQueue.isProcessing {
            return "Syncing \(environment.writeQueue.pendingCount) changes"
        }
        return "\(environment.writeQueue.pendingCount) pending changes"
    }

    static func shouldSyncDrafts(
        hasLoadedDrafts: Bool,
        isDraftDirty: Bool,
        previousUserId: String?,
        nextUserId: String?
    ) -> Bool {
        SettingsDraftSynchronizer.shouldSyncDrafts(
            hasLoadedDrafts: hasLoadedDrafts,
            isDraftDirty: isDraftDirty,
            previousUserId: previousUserId,
            nextUserId: nextUserId
        )
    }

    private static func normalizedUserId(_ value: String?) -> String? {
        SettingsDraftSynchronizer.normalizedUserId(value)
    }
}

struct AgentSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State var selectedPrimaryProvider: AIPrimaryProvider = .anthropic
    @State var providerKeyInput: String = ""

    var body: some View {
        #if os(macOS)
        macAgentSettingsBody
        #else
        Form {
            Section {
                Picker("Provider", selection: $selectedPrimaryProvider) {
                    ForEach(viewModel.supportedPrimaryProviders) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .appFont(.body)
                if selectedProviderHasKey {
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Text(maskedProviderKeyText)
                            .appFont(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        Spacer()

                        Button {
                            Task {
                                await viewModel.deletePrimaryProviderKey(provider: selectedPrimaryProvider)
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isSavingPrimaryProvider)
                        .accessibilityLabel("Clear API Key")
                    }
                } else {
                    SecureField("Enter \(selectedPrimaryProvider.displayName) API key", text: $providerKeyInput)
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    #endif
                    .submitLabel(.done)
                    .disabled(viewModel.isSavingPrimaryProvider)
                    .onSubmit {
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
                }
                if let providerError = viewModel.primaryProviderError, !providerError.isEmpty {
                    Text(providerError)
                        .appFont(.caption)
                        .foregroundStyle(DesignTokens.Colors.error)
                }
            } header: {
                sectionHeader(
                    title: "AI Provider",
                    subtitle: "Choose a provider for \(assistantPossessiveDisplayName) brain."
                )
            }
            Section {
                readOnlySectionText(resolvedText(viewModel.settings?.assistantIdentity?.name))
            } header: {
                sectionHeader(
                    title: Self.assistantSectionTitle("Name", assistantDisplayName: assistantDisplayName),
                    subtitle: "Your assistant's name"
                )
            }
            Section {
                readOnlySectionText(resolvedText(viewModel.settings?.assistantIdentity?.tone))
            } header: {
                sectionHeader(
                    title: Self.assistantSectionTitle("Tone", assistantDisplayName: assistantDisplayName),
                    subtitle: "How \(assistantDisplayName) should sound and respond."
                )
            }
            Section {
                readOnlySectionText(resolvedText(viewModel.settings?.assistantIdentity?.values))
            } header: {
                sectionHeader(
                    title: Self.assistantSectionTitle("Values", assistantDisplayName: assistantDisplayName),
                    subtitle: "Core principles \(assistantDisplayName) prioritizes."
                )
            }
            Section {
                readOnlySectionText(resolvedText(viewModel.settings?.assistantIdentity?.boundaries))
            } header: {
                sectionHeader(
                    title: Self.assistantSectionTitle("Boundaries", assistantDisplayName: assistantDisplayName),
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
                        title: Self.assistantSectionTitle("Identity Meta", assistantDisplayName: assistantDisplayName),
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
                        title: Self.assistantSectionTitle("Soul Meta", assistantDisplayName: assistantDisplayName),
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
        #endif
    }

    func resolvedText(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Not set" : trimmed
    }

    var assistantDisplayName: String {
        viewModel.assistantDisplayName
    }

    var assistantPossessiveDisplayName: String {
        Self.assistantPossessiveDisplayName(assistantDisplayName: assistantDisplayName)
    }

    static func assistantSectionTitle(_ suffix: String, assistantDisplayName: String) -> String {
        "\(assistantPossessiveDisplayName(assistantDisplayName: assistantDisplayName)) \(suffix)"
    }

    static func assistantPossessiveDisplayName(assistantDisplayName: String) -> String {
        "\(assistantDisplayName)'s"
    }

    var primaryProviderSignature: String {
        viewModel.settings?.aiPrimaryProvider ?? ""
    }

    var selectedProviderHasKey: Bool {
        guard viewModel.settings?.aiPrimaryProvider == selectedPrimaryProvider.rawValue else {
            return false
        }
        return viewModel.settings?.aiPrimaryProviderHasKey ?? false
    }

    var selectedProviderKeyLast4: String? {
        guard viewModel.settings?.aiPrimaryProvider == selectedPrimaryProvider.rawValue else {
            return nil
        }
        return viewModel.settings?.aiPrimaryProviderKeyLast4
    }

    var maskedProviderKeyText: String {
        "••••••••\(selectedProviderKeyLast4 ?? "----")"
    }

    func syncSelectedProvider(from settings: UserSettings?) {
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
                .appFont(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
