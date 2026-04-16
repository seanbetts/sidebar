import Foundation
import sideBarShared

final class NotesWriteQueueExecutor: WriteQueueExecutor {
    private let api: any NotesProviding
    private let store: any NotesWriteQueueApplying
    private let decoder = JSONDecoder()
    private lazy var noteHandlers: [WriteOperation: (PendingWriteRecord) async throws -> Void] = [
        .create: handleCreate,
        .update: handleUpdate,
        .move: handleMove,
        .archive: handleArchive,
        .pin: handlePin,
        .delete: handleDelete
    ]
    private lazy var folderHandlers: [WriteOperation: (PendingWriteRecord) async throws -> Void] = [
        .create: handleCreateFolder,
        .rename: handleRenameFolder,
        .delete: handleDeleteFolder
    ]

    init(api: any NotesProviding, store: any NotesWriteQueueApplying) {
        self.api = api
        self.store = store
    }

    func execute(write: PendingWriteRecord) async throws {
        guard let operation = WriteOperation(rawValue: write.operationType) else {
            return
        }
        guard let entityType = WriteEntityType(rawValue: write.entityType) else {
            return
        }
        let handler: ((PendingWriteRecord) async throws -> Void)?
        switch entityType {
        case .note:
            handler = noteHandlers[operation]
        case .noteFolder:
            handler = folderHandlers[operation]
        default:
            handler = nil
        }
        guard let handler else { return }
        try await handler(write)
    }

    private func handleCreate(_ write: PendingWriteRecord) async throws {
        let payload = try decoder.decode(NoteCreateRequest.self, from: write.payload)
        let created = try await api.createNote(request: payload)
        store.applyEditorUpdate(created)
        try await store.loadTree(force: true)
    }

    private func handleUpdate(_ write: PendingWriteRecord) async throws {
        guard let noteId = write.entityId else { return }
        let payload = try decoder.decode(NoteUpdateRequest.self, from: write.payload)
        // Note content edits are local-authoritative when replayed from the queue.
        // The live API update path does not send a conflict timestamp, so queued
        // note edits should also overwrite the latest server copy instead of pausing
        // the entire write queue behind a manual conflict sheet.
        let updated = try await api.updateNote(id: noteId, document: payload.document)
        store.applyEditorUpdate(updated)
    }

    private func handleMove(_ write: PendingWriteRecord) async throws {
        guard let noteId = write.entityId else { return }
        let payload = try decoder.decode(MoveRequest.self, from: write.payload)
        let updated = try await api.moveNote(id: noteId, folder: payload.folder)
        store.applyEditorUpdate(updated)
    }

    private func handleArchive(_ write: PendingWriteRecord) async throws {
        guard let noteId = write.entityId else { return }
        let payload = try decoder.decode(ArchiveRequest.self, from: write.payload)
        let updated = try await api.archiveNote(id: noteId, archived: payload.archived)
        store.applyEditorUpdate(updated)
    }

    private func handlePin(_ write: PendingWriteRecord) async throws {
        guard let noteId = write.entityId else { return }
        let payload = try decoder.decode(PinRequest.self, from: write.payload)
        let updated = try await api.pinNote(id: noteId, pinned: payload.pinned)
        store.applyEditorUpdate(updated)
    }

    private func handleDelete(_ write: PendingWriteRecord) async throws {
        guard let noteId = write.entityId else { return }
        do {
            _ = try await api.deleteNote(id: noteId)
        } catch let error as APIClientError {
            if case .requestFailed(let statusCode) = error, statusCode != 404 {
                throw error
            }
        }
        store.invalidateNote(id: noteId)
    }

    private func handleCreateFolder(_ write: PendingWriteRecord) async throws {
        let payload = try decoder.decode(NoteFolderCreateRequest.self, from: write.payload)
        try await api.createFolder(path: payload.path)
        try await store.loadTree(force: true)
    }

    private func handleRenameFolder(_ write: PendingWriteRecord) async throws {
        let payload = try decoder.decode(NoteFolderRenameRequest.self, from: write.payload)
        try await api.renameFolder(oldPath: payload.oldPath, newName: payload.newName)
        try await store.loadTree(force: true)
    }

    private func handleDeleteFolder(_ write: PendingWriteRecord) async throws {
        let payload = try decoder.decode(NoteFolderDeleteRequest.self, from: write.payload)
        try await api.deleteFolder(path: payload.path)
        try await store.loadTree(force: true)
    }
}
