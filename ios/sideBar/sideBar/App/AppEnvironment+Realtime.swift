import Foundation

extension AppEnvironment: RealtimeEventHandler {
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
        Task {
            await notesViewModel.applyRealtimeEvent(payload)
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
