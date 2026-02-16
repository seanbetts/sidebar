import SwiftUI
import sideBarShared

struct SystemSettingsView: View {
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
                Text("Customize the prompts that guide sideBar")
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
                        ProgressView()
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
                ProgressView()
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
        [communicationStyle, workingRelationship].joined(separator: "|")
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
            await viewModel.saveSystemSettings(
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
