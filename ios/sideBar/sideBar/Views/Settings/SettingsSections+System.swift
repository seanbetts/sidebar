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
                Text("Customize how the assistant should collaborate with you")
                    .foregroundStyle(.secondary)
            }
            Section("Communication Style") {
                TextEditor(text: $communicationStyle)
                .frame(minHeight: 120)
            }
            Section("Working Relationship") {
                TextEditor(text: $workingRelationship)
                    .frame(minHeight: 120)
            }
            if viewModel.isSavingSystem {
                Section {
                    HStack(spacing: 8) {
                        LoadingIndicatorView(size: LoadingIndicatorSize.inline)
                        Text("Saving settings...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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

    var body: some View {
        Form {
            Section {
                Text("Managed by the assistant. User edits are disabled for these fields.")
                    .foregroundStyle(.secondary)
            }
            Section("Assistant Name") {
                Text(resolvedText(viewModel.settings?.assistantIdentity?.name))
                    .textSelection(.enabled)
            }
            Section("Assistant Tone") {
                Text(resolvedText(viewModel.settings?.assistantIdentity?.tone))
                    .textSelection(.enabled)
            }
            Section("Assistant Values") {
                Text(resolvedText(viewModel.settings?.assistantIdentity?.values))
                    .textSelection(.enabled)
            }
            Section("Assistant Boundaries") {
                Text(resolvedText(viewModel.settings?.assistantIdentity?.boundaries))
                    .textSelection(.enabled)
            }
            if let identityMeta = viewModel.settings?.assistantIdentityMeta {
                Section("Assistant Identity Meta") {
                    Text("Updated: \(identityMeta.updatedAt)")
                    Text("Version: \(identityMeta.version)")
                    if let reason = identityMeta.reason, !reason.isEmpty {
                        Text("Reason: \(reason)")
                    }
                }
            }
            Section("Soul Purpose") {
                Text(resolvedText(viewModel.settings?.assistantSoul?.purpose))
                    .textSelection(.enabled)
            }
            Section("Soul Operating Principles") {
                Text(resolvedText(viewModel.settings?.assistantSoul?.operatingPrinciples))
                    .textSelection(.enabled)
            }
            Section("Soul Adaptation Policy") {
                Text(resolvedText(viewModel.settings?.assistantSoul?.adaptationPolicy))
                    .textSelection(.enabled)
            }
            Section("Soul Success Signals") {
                Text(resolvedText(viewModel.settings?.assistantSoul?.successSignals))
                    .textSelection(.enabled)
            }
            if let soulMeta = viewModel.settings?.assistantSoulMeta {
                Section("Assistant Soul Meta") {
                    Text("Updated: \(soulMeta.updatedAt)")
                    Text("Version: \(soulMeta.version)")
                    if let reason = soulMeta.reason, !reason.isEmpty {
                        Text("Reason: \(reason)")
                    }
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
    }

    private func resolvedText(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Not set" : trimmed
    }
}
