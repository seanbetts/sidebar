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
    func removePendingTaskPlaceholder(operationId: String)
    func lastSyncToken() -> String?
    func updateLastSyncToken(_ token: String?)
    func refreshAfterSync() async
}

@MainActor
protocol WebsitesWriteQueueApplying {
    func applySyncItem(_ item: WebsiteItem)
}
