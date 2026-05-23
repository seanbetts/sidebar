import Foundation

extension AppEnvironment: RealtimeEventHandler {
    func configureTaskRealtimeInvalidationHandler() {
        tasksViewModel.onRealtimeInvalidation = { [weak self] change in
            guard let self else { return }
            await refreshCoordinator.scheduleRealtimeInvalidation(
                change,
                context: currentRefreshContext()
            )
        }
    }

    var currentSyncHealth: SyncHealthState {
        SyncHealthModel.evaluate(
            canAttemptServerRead: connectivityMonitor.canAttemptServerRead &&
                protectedContentReadiness.canAttemptServerRead,
            realtimeConnected: (realtimeClient as? SupabaseRealtimeAdapter)?.isRealtimeConnected ?? false,
            hasPendingReconnectRefresh: syncCoordinator.hasPendingReconnectRefresh,
            lastRefreshSucceeded: syncCoordinator.lastReconnectRefreshSucceeded
        )
    }

    func allowsFallbackPolling(section: AppSection, hasActiveJob: Bool = false) -> Bool {
        guard currentSyncHealth.allowsFallbackPolling else {
            return false
        }
        return currentRefreshContext().visibleSection == section || hasActiveJob
    }

    public func handleNoteEvent(_ payload: RealtimePayload<NoteRealtimeRecord>) {
        let title = payload.record?.title ?? payload.oldRecord?.title
        if title == ScratchpadConstants.title {
            scratchpadStore.bump()
            return
        }
        guard let noteId = payload.record?.id ?? payload.oldRecord?.id else {
            Task {
                await refreshCoordinator.scheduleDecodeFailureRefresh(
                    section: .notes,
                    context: currentRefreshContext()
                )
            }
            return
        }
        let updatedAt = DateParsing.parseISO8601(payload.record?.updatedAt ?? payload.oldRecord?.updatedAt)
        let isDeleted = payload.eventType == .delete || payload.record?.deletedAt != nil
        let change = NotesRefreshAdapter(viewModel: notesViewModel).classifyNoteRealtime(
            noteId: noteId,
            updatedAt: updatedAt,
            isDeleted: isDeleted
        )
        Task {
            await refreshCoordinator.scheduleRealtimeInvalidation(change, context: currentRefreshContext())
        }
    }

    public func handleWebsiteEvent(_ payload: RealtimePayload<WebsiteRealtimeRecord>) {
        Task {
            await websitesViewModel.applyRealtimeEvent(payload)
        }
    }

    public func handleIngestedFileEvent(_ payload: RealtimePayload<IngestedFileRealtimeRecord>) {
        Task {
            await ingestionViewModel.applyIngestedFileEvent(payload)
        }
    }

    public func handleFileJobEvent(_ payload: RealtimePayload<FileJobRealtimeRecord>) {
        Task {
            await ingestionViewModel.applyFileJobEvent(payload)
        }
    }

    public func handleTaskEvent(_ payload: RealtimePayload<TaskRealtimeRecord>) {
        Task {
            await tasksViewModel.applyTaskRealtimeEvent(payload)
        }
    }

    public func handleTaskProjectEvent(_ payload: RealtimePayload<TaskProjectRealtimeRecord>) {
        Task {
            await tasksViewModel.applyTaskProjectRealtimeEvent(payload)
        }
    }

    public func handleTaskGroupEvent(_ payload: RealtimePayload<TaskGroupRealtimeRecord>) {
        Task {
            await tasksViewModel.applyTaskGroupRealtimeEvent(payload)
        }
    }
}
