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
    @Environment(\.dismiss) private var dismiss
    let skill: SkillItem
    let isStoreActionBusy: Bool
    let isInstalled: Bool
    let installError: String?
    let onInstallTap: () -> Void
    let onConfirmUninstall: () async -> Void

    @State private var showUninstallPrompt = false

    var body: some View {
        MacModalShell(type: storeSkillDetailPanelType()) {
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
                #if os(macOS)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(appIcon: AppIcon.Action.close)
                        }
                        .accessibilityLabel("Close skill details")
                        .keyboardShortcut(.cancelAction)
                    }
                }
                #endif
                .destructiveConfirmationAlert(
                    title: "Uninstall skill?",
                    isPresented: $showUninstallPrompt,
                    message: "This will uninstall \(viewModel.displayName(for: skill)).",
                    confirmTitle: "Uninstall",
                    onConfirm: {
                        Task {
                            await onConfirmUninstall()
                        }
                    },
                    onCancel: {
                        showUninstallPrompt = false
                    }
                )
            }
        }
        .settingsSheetGrabBarVisible()
    }
}
