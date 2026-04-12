import Foundation

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
}
