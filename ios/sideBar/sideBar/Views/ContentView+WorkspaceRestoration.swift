import SwiftUI
import sideBarShared

extension ContentView {
    var currentRestorationUserId: String? {
        environment.container.authSession.userId
    }

    var hasMeaningfulChatDraftForRestoration: Bool {
        !environment.chatViewModel.draftText.trimmed.isEmpty
            || !environment.chatViewModel.attachments.isEmpty
    }

    func saveCurrentWorkspaceRestorationSnapshot() {
        guard environment.isAuthenticated else { return }

        let family: DeviceWorkspaceFamily = isPhoneIdiom ? .phone : .workspace
        let snapshot: DeviceWorkspaceSnapshot
        switch family {
        case .phone:
            snapshot = DeviceWorkspaceSnapshot(
                schemaVersion: DeviceWorkspaceSnapshot.currentSchemaVersion,
                userId: currentRestorationUserId,
                family: .phone,
                updatedAt: Date(),
                phoneRoute: currentPhoneWorkspaceRoute(),
                splitWorkspace: nil
            )
        case .workspace:
            snapshot = DeviceWorkspaceSnapshot(
                schemaVersion: DeviceWorkspaceSnapshot.currentSchemaVersion,
                userId: currentRestorationUserId,
                family: .workspace,
                updatedAt: Date(),
                phoneRoute: nil,
                splitWorkspace: currentSplitWorkspaceSnapshot()
            )
        }
        environment.workspaceRestorationStore.save(snapshot)
    }

    func currentPhoneWorkspaceRoute() -> PhoneWorkspaceRoute {
        WorkspaceRestorationPlanner.makePhoneRoute(
            section: compactWorkspaceSection,
            selectedConversationId: environment.chatViewModel.selectedConversationId,
            isDraftConversationActive: environment.chatViewModel.isDraftConversationActive,
            hasMeaningfulChatDraft: hasMeaningfulChatDraftForRestoration,
            selectedNoteId: environment.notesRuntime.viewModel.selectedNoteId,
            selectedTaskRouteId: environment.tasksPhoneDetailRouteId,
            selectedWebsiteId: environment.websitesViewModel.selectedWebsiteId,
            selectedFileId: environment.ingestionViewModel.selectedFileId
        )
    }

    func currentSplitWorkspaceSnapshot() -> SplitWorkspaceSnapshot {
        SplitWorkspaceSnapshot(
            sidebarSelection: sidebarSelection,
            primaryDescriptor: WorkspaceDescriptorSnapshot(
                descriptor: primaryWorkspaceDescriptor
            ),
            secondaryDescriptor: WorkspaceDescriptorSnapshot(
                descriptor: secondaryWorkspaceDescriptor
            ),
            focusedPane: environment.focusedWorkspacePane ?? .primary,
            isLeftPanelExpanded: isLeftPanelExpanded,
            isWorkspaceExpanded: isWorkspaceExpanded
        )
    }
}
