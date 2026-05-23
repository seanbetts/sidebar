import Foundation
import sideBarShared

// MARK: - IngestionViewModel+Realtime
extension IngestionViewModel {
    public func applyIngestedFileEvent(_ payload: RealtimePayload<IngestedFileRealtimeRecord>) async {
        store.applyIngestedFileEvent(payload)
        if let selectedFileId, selectedFileId == payload.record?.id || selectedFileId == payload.oldRecord?.id {
            _ = await loadMeta(fileId: selectedFileId)
        }
    }

    public func applyFileJobEvent(_ payload: RealtimePayload<FileJobRealtimeRecord>) async {
        guard let record = payload.record else { return }
        if shouldRegisterFileJobRealtime(fileId: record.fileId) {
            registerFileJobProgress(fileId: record.fileId)
        }
        store.applyFileJobEvent(payload)

        let mapped = RealtimeMappers.mapFileJob(record)
        let result = await jobProgressCoordinator.applyRealtimeStatus(
            jobId: record.fileId,
            status: AsyncJobStatus(rawValue: mapped.status ?? ""),
            userMessage: mapped.errorMessage
        )
        if FileJobStatusPolicy.isSuccessfulTerminal(mapped.status) {
            await ensureViewerReady(for: record.fileId)
        }
        guard case .terminal = result else { return }

        cancelJobPolling(fileId: record.fileId)
        await onJobTerminalState(
            FilesRefreshAdapter.jobTerminalChange(
                entityId: record.fileId,
                requiresDetailRefresh: selectedFileId == record.fileId
            )
        )
    }

    private func shouldRegisterFileJobRealtime(fileId: String) -> Bool {
        guard IdentifierValidation.isServerFileID(fileId) else { return false }
        if let item = items.first(where: { $0.file.id == fileId }),
           FileJobStatusPolicy.isActive(item.statusValue) {
            return true
        }
        if let activeMeta, activeMeta.file.id == fileId,
           FileJobStatusPolicy.isActive(activeMeta.job.status) {
            return true
        }
        return false
    }
}
