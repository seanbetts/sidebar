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
}
