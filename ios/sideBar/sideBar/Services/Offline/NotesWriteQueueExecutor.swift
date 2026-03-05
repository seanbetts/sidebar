import Foundation
import OSLog
import sideBarShared

final class NotesWriteQueueExecutor: WriteQueueExecutor {
    private let api: any NotesProviding
    private let store: any NotesWriteQueueApplying
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let logger = Logger(subsystem: "sideBar", category: "NotesWriteQueueExecutor")
    private lazy var noteHandlers: [WriteOperation: (PendingWriteRecord) async throws -> Void] = [
        .update: handleUpdate,
        .move: handleMove,
        .archive: handleArchive,
        .pin: handlePin,
        .delete: handleDelete
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
        guard entityType == .note else { return }
        guard let handler = noteHandlers[operation] else { return }
        try await handler(write)
    }

    private func handleUpdate(_ write: PendingWriteRecord) async throws {
        guard let noteId = write.entityId else { return }
        try await checkForConflictIfNeeded(noteId: noteId, write: write)
        let payload = try decoder.decode(NoteUpdateRequest.self, from: write.payload)
        let normalized = NotesRichTextCodec.normalizeWriteInput(
            content: payload.content,
            plainText: payload.plainText
        )
        let updated = try await api.updateNote(id: noteId, content: normalized.content)
        store.applyEditorUpdate(updated)
    }

    private func handleMove(_ write: PendingWriteRecord) async throws {
        guard let noteId = write.entityId else { return }
        try await checkForConflictIfNeeded(noteId: noteId, write: write)
        let payload = try decoder.decode(MoveRequest.self, from: write.payload)
        let updated = try await api.moveNote(id: noteId, folder: payload.folder)
        store.applyEditorUpdate(updated)
        await refreshTreeAfterMutation()
    }

    private func handleArchive(_ write: PendingWriteRecord) async throws {
        guard let noteId = write.entityId else { return }
        try await checkForConflictIfNeeded(noteId: noteId, write: write)
        let payload = try decoder.decode(ArchiveRequest.self, from: write.payload)
        let updated = try await api.archiveNote(id: noteId, archived: payload.archived)
        store.applyEditorUpdate(updated)
        await refreshTreeAfterMutation()
    }

    private func handlePin(_ write: PendingWriteRecord) async throws {
        guard let noteId = write.entityId else { return }
        try await checkForConflictIfNeeded(noteId: noteId, write: write)
        let payload = try decoder.decode(PinRequest.self, from: write.payload)
        let updated = try await api.pinNote(id: noteId, pinned: payload.pinned)
        store.applyEditorUpdate(updated)
        await refreshTreeAfterMutation()
    }

    private func handleDelete(_ write: PendingWriteRecord) async throws {
        guard let noteId = write.entityId else { return }
        try await checkForConflictIfNeeded(noteId: noteId, write: write, allowNotFound: true)
        do {
            _ = try await api.deleteNote(id: noteId)
        } catch let error as APIClientError {
            if case .requestFailed(let statusCode) = error, statusCode != 404 {
                throw error
            }
        }
        store.invalidateNote(id: noteId)
        await refreshTreeAfterMutation()
    }

    private func checkForConflictIfNeeded(
        noteId: String,
        write: PendingWriteRecord,
        allowNotFound: Bool = false
    ) async throws {
        guard let snapshotData = write.serverSnapshot else {
            return
        }
        let snapshot: ServerSnapshot
        do {
            snapshot = try decoder.decode(ServerSnapshot.self, from: snapshotData)
        } catch {
            logger.error("Failed to decode note server snapshot for conflict check: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard case let .note(noteSnapshot) = snapshot.payload,
              let snapshotModified = noteSnapshot.modified else { return }

        do {
            let serverNote = try await api.getNote(id: noteId)
            if serverNote.modified != snapshotModified {
                let serverSnapshot = ServerSnapshot(
                    entityType: .note,
                    entityId: noteId,
                    capturedAt: Date(),
                    payload: .note(
                        NoteSnapshot(
                            modified: serverNote.modified,
                            name: serverNote.name,
                            path: serverNote.path,
                            pinned: nil,
                            pinnedOrder: nil,
                            archived: nil
                        )
                    )
                )
                let encoded: Data?
                do {
                    encoded = try encoder.encode(serverSnapshot)
                } catch {
                    logger.error("Failed to encode note conflict snapshot: \(error.localizedDescription, privacy: .public)")
                    encoded = nil
                }
                throw WriteQueueConflictError(
                    reason: "Note changed on another device.",
                    serverSnapshot: encoded
                )
            }
        } catch let error as APIClientError {
            if case .requestFailed(let statusCode) = error, statusCode == 404, allowNotFound {
                return
            }
            throw error
        }
    }

    private func refreshTreeAfterMutation() async {
        do {
            try await store.loadTree(force: true)
        } catch {
            logger.error("Failed to refresh note tree after queued write: \(error.localizedDescription, privacy: .public)")
        }
    }
}
