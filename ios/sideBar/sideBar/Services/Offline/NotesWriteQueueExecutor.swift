import Foundation

final class NotesWriteQueueExecutor: WriteQueueExecutor {
    private let api: any NotesProviding
    private let store: NotesStore
    private let decoder = JSONDecoder()

    init(api: any NotesProviding, store: NotesStore) {
        self.api = api
        self.store = store
    }

    func execute(write: PendingWrite) async throws {
        guard let operation = WriteOperation(rawValue: write.operationType) else {
            return
        }
        guard let entityType = WriteEntityType(rawValue: write.entityType) else {
            return
        }
        switch (operation, entityType) {
        case (.update, .note):
            guard let noteId = write.entityId else { return }
            let payload = try decoder.decode(NoteUpdateRequest.self, from: write.payload)
            let updated = try await api.updateNote(id: noteId, content: payload.content)
            store.applyEditorUpdate(updated)
        default:
            return
        }
    }
}
