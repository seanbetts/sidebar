import SwiftUI
import sideBarShared

struct StoreInstallPrompt: Identifiable {
    let skill: SkillItem
    let missingProviders: [String]

    var id: String { skill.id }
}

struct StoreUninstallPrompt: Identifiable {
    let skill: SkillItem

    var id: String { skill.id }
}

struct StoreSkillDetailSheet: View {
    @ObservedObject var viewModel: SettingsViewModel
    let skill: SkillItem
    let isStoreActionBusy: Bool
    let isInstalled: Bool
    let installError: String?
    let onInstallTap: () -> Void
    let onConfirmUninstall: () async -> Void

    @State private var showUninstallPrompt = false

    var body: some View {
        NavigationStack {
            StoreSkillConfigView(
                viewModel: viewModel,
                skill: skill,
                isStoreActionBusy: isStoreActionBusy,
                isInstalled: isInstalled,
                installError: installError,
                onInstallTap: onInstallTap,
                onInstalledTap: {
                    showUninstallPrompt = true
                }
            )
            .alert("Uninstall skill?", isPresented: $showUninstallPrompt) {
                Button("Uninstall", role: .destructive) {
                    Task {
                        await onConfirmUninstall()
                    }
                }
                Button("Cancel", role: .cancel) {
                    showUninstallPrompt = false
                }
            } message: {
                Text("This will uninstall \(viewModel.displayName(for: skill)).")
            }
        }
        .settingsSheetGrabBarVisible()
    }
}
