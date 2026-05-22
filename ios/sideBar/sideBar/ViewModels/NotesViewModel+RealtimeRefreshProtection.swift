import Foundation

extension NotesViewModel {
    func refreshSelectedNoteForRealtime() async {
        guard let noteId = selectedNoteId ?? activeNote?.path ?? activeNote?.id else { return }
        let protection = protectRealtimeDetailRefresh(noteId: noteId)
        let result = await loadNoteForRealtime(id: noteId)
        if result.didLoad, result.didPublishActiveNote {
            markRealtimeDetailRefreshProtectionReady(protection)
            scheduleRealtimeDetailRefreshProtectionCleanup(protection)
        } else {
            clearRealtimeDetailRefreshProtectionIfCurrent(protection)
        }
    }

    func isSelectedNoteRealtimeIdentifier(_ noteId: String) -> Bool {
        let active = activeNote ?? store.activeNote
        if selectedNoteId == noteId || pendingNoteId == noteId || active?.id == noteId || active?.path == noteId {
            return true
        }
        let selectedIdentifiers = selectedNoteRealtimeIdentifiers()
        let payload = store.notePayload(forId: noteId) ?? store.notePayload(forPath: noteId)
        if let payload, selectedIdentifiers.contains(payload.id) || selectedIdentifiers.contains(payload.path) {
            return true
        }
        return selectedIdentifiers.contains { identifier in
            guard let payload = store.notePayload(forPath: identifier) ?? store.notePayload(forId: identifier) else {
                return false
            }
            return payload.id == noteId || payload.path == noteId
        }
    }

    func realtimeDetailRefreshUpdateProtection(for note: NotePayload) -> RealtimeDetailRefreshUpdateProtection {
        guard let protection = protectedRealtimeDetailRefresh,
              protection.identifiers.contains(note.id) || protection.identifiers.contains(note.path) else {
            return .none
        }
        let isExpectedDetailNote = protection.expectedDetailNote == note
        if isExpectedDetailNote {
            protectedRealtimeDetailRefresh = nil
        }
        if let acceptedSaveAcknowledgement = protection.acceptedSaveAcknowledgement,
           isAcceptedSaveAcknowledgement(note, matching: acceptedSaveAcknowledgement) {
            return .acceptedSaveAcknowledgement
        }
        let shouldSuppressRegardlessOfQueue = isExpectedDetailNote && protection.acceptedSaveAcknowledgement != nil
        return .protectedRealtimeDetail(suppressRegardlessOfQueue: shouldSuppressRegardlessOfQueue)
    }

    func markAcceptedSaveAcknowledgementForRealtimeProtection(_ note: NotePayload) {
        guard let protection = protectedRealtimeDetailRefresh,
              protection.identifiers.contains(note.id) || protection.identifiers.contains(note.path) else {
            return
        }
        protectedRealtimeDetailRefresh?.acceptedSaveAcknowledgement = note
    }

    func markNoteQueuedForSync(noteId: String) {
        realtimeProtectedQueuedDraftIdentifiers.formUnion(noteIdentifiers(matching: noteId))
    }

    func clearNoteQueuedForSync(_ note: NotePayload) {
        realtimeProtectedQueuedDraftIdentifiers.subtract(noteIdentifiers(matching: note.id))
        realtimeProtectedQueuedDraftIdentifiers.subtract(noteIdentifiers(matching: note.path))
    }

    func clearSelectedNoteForRealtimeDeletion(noteId: String) {
        guard isSelectedNoteRealtimeIdentifier(noteId) else { return }
        protectedRealtimeDetailRefresh = nil
        selectedNoteId = nil
        pendingNoteId = nil
        activeNote = nil
        store.invalidateNote(id: noteId)
        store.clearActiveNote()
    }

    private func isAcceptedSaveAcknowledgement(_ note: NotePayload, matching acknowledged: NotePayload) -> Bool {
        (note.id == acknowledged.id || note.path == acknowledged.path) &&
            note.document == acknowledged.document &&
            note.documentVersion == acknowledged.documentVersion &&
            note.plainText == acknowledged.plainText
    }

    private func protectRealtimeDetailRefresh(noteId: String) -> RealtimeDetailRefreshProtection {
        let protection = RealtimeDetailRefreshProtection(
            identifiers: noteIdentifiers(matching: noteId),
            expectedDetailNote: nil,
            acceptedSaveAcknowledgement: nil
        )
        protectedRealtimeDetailRefresh = protection
        return protection
    }

    private func loadNoteForRealtime(id: String) async -> RealtimeNoteLoadResult {
        errorMessage = nil
        selectedNoteId = id
        if !notesOfflineCapabilityPolicy.canAttemptServerRead, !store.hasCachedNote(id: id) {
            errorMessage = "This note isn't available offline yet."
            pendingNoteId = id
            return RealtimeNoteLoadResult(didLoad: false, didPublishActiveNote: false)
        }
        if hasRealtimeProtectedQueuedDraft(noteId: id) {
            return await fetchRealtimeNoteWithoutApplying(id: id)
        }
        return await loadRealtimeNoteIntoStore(id: id)
    }

    private func fetchRealtimeNoteWithoutApplying(id: String) async -> RealtimeNoteLoadResult {
        do {
            _ = try await api.getNote(id: id)
            pendingNoteId = nil
            return RealtimeNoteLoadResult(didLoad: true, didPublishActiveNote: false)
        } catch {
            if activeNote == nil {
                errorMessage = ErrorMapping.message(for: error)
            }
            return RealtimeNoteLoadResult(didLoad: false, didPublishActiveNote: false)
        }
    }

    private func loadRealtimeNoteIntoStore(id: String) async -> RealtimeNoteLoadResult {
        let previousActiveNote = store.activeNote
        do {
            try await store.loadNote(id: id, force: true)
            pendingNoteId = nil
            return RealtimeNoteLoadResult(didLoad: true, didPublishActiveNote: previousActiveNote != store.activeNote)
        } catch {
            if activeNote == nil {
                errorMessage = ErrorMapping.message(for: error)
            }
            return RealtimeNoteLoadResult(didLoad: false, didPublishActiveNote: false)
        }
    }

    private func hasRealtimeProtectedQueuedDraft(noteId: String) -> Bool {
        !realtimeProtectedQueuedDraftIdentifiers.isDisjoint(with: noteIdentifiers(matching: noteId))
    }

    private func markRealtimeDetailRefreshProtectionReady(_ protection: RealtimeDetailRefreshProtection) {
        guard protectedRealtimeDetailRefresh?.id == protection.id else { return }
        protectedRealtimeDetailRefresh?.expectedDetailNote = store.activeNote
    }

    private func scheduleRealtimeDetailRefreshProtectionCleanup(_ protection: RealtimeDetailRefreshProtection) {
        Task { @MainActor [weak self] in
            for _ in 0..<3 {
                await Task.yield()
            }
            self?.clearRealtimeDetailRefreshProtectionIfCurrent(protection)
        }
    }

    private func clearRealtimeDetailRefreshProtectionIfCurrent(_ protection: RealtimeDetailRefreshProtection) {
        if protectedRealtimeDetailRefresh == protection {
            protectedRealtimeDetailRefresh = nil
        }
    }

    private func noteIdentifiers(matching noteId: String) -> Set<String> {
        var identifiers = Set([noteId])
        if let selectedNoteId {
            identifiers.insert(selectedNoteId)
        }
        if let pendingNoteId {
            identifiers.insert(pendingNoteId)
        }
        if let activeNote {
            identifiers.insert(activeNote.id)
            identifiers.insert(activeNote.path)
        }
        if let storeActiveNote = store.activeNote {
            identifiers.insert(storeActiveNote.id)
            identifiers.insert(storeActiveNote.path)
        }
        return identifiers
    }

    private func selectedNoteRealtimeIdentifiers() -> Set<String> {
        var identifiers = Set<String>()
        if let selectedNoteId {
            identifiers.insert(selectedNoteId)
        }
        if let pendingNoteId {
            identifiers.insert(pendingNoteId)
        }
        if let activeNote {
            identifiers.insert(activeNote.id)
            identifiers.insert(activeNote.path)
        }
        if let storeActiveNote = store.activeNote {
            identifiers.insert(storeActiveNote.id)
            identifiers.insert(storeActiveNote.path)
        }
        return identifiers
    }
}
