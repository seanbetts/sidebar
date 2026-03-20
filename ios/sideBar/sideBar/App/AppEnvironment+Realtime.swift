import Foundation

extension AppEnvironment: RealtimeEventHandler {
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

    public func handleWebsiteJobEvent(_ payload: RealtimePayload<WebsiteJobRealtimeRecord>) {
        guard let record = payload.record else { return }
        Task {
            websitesViewModel.didReceiveWebsiteJobUpdate(
                jobId: record.id,
                status: record.status,
                websiteId: record.websiteId,
                errorMessage: record.errorMessage
            )
        }
    }
}
