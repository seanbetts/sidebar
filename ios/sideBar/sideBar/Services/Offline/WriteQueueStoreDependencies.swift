import Foundation
import sideBarShared

@MainActor
protocol FilesWriteQueueApplying {
    func applySyncFile(_ file: IngestedFileMeta)
}

@MainActor
protocol NotesWriteQueueApplying {
    func applyEditorUpdate(_ note: NotePayload)
    func invalidateNote(id: String)
    func loadTree(force: Bool) async throws
}

@MainActor
protocol TasksWriteQueueApplying {
    func applySyncResponse(_ response: TaskSyncResponse, operationId: String)
    func pendingPlaceholderId(operationId: String) -> String?
    func remapPendingTaskReferences(localID: String, serverID: String) async
    func removePendingTaskPlaceholder(operationId: String)
    func lastSyncToken() -> String?
    func updateLastSyncToken(_ token: String?)
    func refreshAfterSync() async
}

@MainActor
protocol WebsitesWriteQueueApplying {
    func applySyncItem(_ item: WebsiteItem)
    func applySyncItems(_ items: [WebsiteItem])
}

extension WebsitesWriteQueueApplying {
    func applySyncItems(_ items: [WebsiteItem]) {
        items.forEach(applySyncItem)
    }
}
