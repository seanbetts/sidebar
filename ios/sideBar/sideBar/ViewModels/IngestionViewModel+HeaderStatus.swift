import Foundation

private enum IngestionHeaderActionError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case let .unavailable(message):
            return message
        }
    }
}

@MainActor
extension IngestionViewModel {
    func registerHeaderReadyEvent(_ notification: ReadyFileNotification) {
        latestHeaderReadyEvent = notification
        lastReadyMessage = notification
    }

    var headerStatusSnapshot: HeaderIngestionStatusSnapshot? {
        let activeRows = activeUploadItems.compactMap(makeHeaderActiveRow)
        if !activeRows.isEmpty {
            return .active(rows: activeRows)
        }

        if let latestHeaderReadyEvent {
            return .success(
                messageID: latestHeaderReadyEvent.fileId,
                title: "Ready",
                message: "\(latestHeaderReadyEvent.filename) is ready."
            )
        }

        guard let failedItem = failedUploadItems.first(where: shouldShowHeaderFailure(for:)) else {
            return nil
        }

        return .failureWithoutAction(
            messageID: failedItem.file.id,
            title: "Upload failed",
            message: failedItem.job.userMessage ?? failedItem.job.errorMessage ?? "This file can't be retried here."
        )
    }

    private func makeHeaderActiveRow(for item: IngestionListItem) -> HeaderStatusRowModel? {
        guard canCancelIngestion(fileId: item.file.id) else { return nil }

        return HeaderStatusRowModel(
            id: item.file.id,
            title: item.file.filenameOriginal,
            detail: ingestionStatusLabel(for: item.job),
            actions: [
                HeaderStatusActionModel(id: "cancel", title: "Cancel", role: .cancel)
            ]
        )
    }

    private func shouldShowHeaderFailure(for item: IngestionListItem) -> Bool {
        !canRetryFailedUpload(fileId: item.file.id) && !canCancelIngestion(fileId: item.file.id)
    }

    func cancelHeaderIngestion(fileId: String) async throws {
        guard items.contains(where: { $0.file.id == fileId }) else {
            throw IngestionHeaderActionError.unavailable("This file is no longer available.")
        }

        guard canCancelIngestion(fileId: fileId) else {
            throw IngestionHeaderActionError.unavailable("This file can't be canceled here.")
        }

        if fileId.hasPrefix("local-") {
            cancelUpload(fileId: fileId)
            return
        }

        guard IdentifierValidation.isServerFileID(fileId) else {
            throw IngestionHeaderActionError.unavailable("Can't cancel this file yet.")
        }

        if isOfflineForIngestion() {
            throw IngestionHeaderActionError.unavailable("Can't cancel while offline.")
        }

        do {
            try await api.cancel(fileId: fileId)
            if selectedFileId == fileId {
                clearSelection()
            }
            store.removeItem(fileId: fileId)
            cancelJobPolling(fileId: fileId)
        } catch {
            throw IngestionHeaderActionError.unavailable("Failed to cancel ingestion.")
        }
    }
}
