import Foundation
import sideBarShared

extension IngestionViewModel {
    func startUpload(url: URL) {
        _ = startUpload(url: url, cleanupOnCompletion: nil)
    }

    func startPendingShareUpload(url: URL) -> Bool {
        startUpload(url: url, cleanupOnCompletion: url)
    }

    private func startUpload(url: URL, cleanupOnCompletion: URL?) -> Bool {
        let filename = url.lastPathComponent
        let mimeType = mimeTypeFor(url: url)
        if let rejectionMessage = uploadValidationMessage(for: url, mimeType: mimeType) {
            toastCenter.show(message: rejectionMessage)
            cleanupTemporaryPendingShareUpload(cleanupOnCompletion)
            return false
        }
        if isOfflineForIngestion() {
            if cleanupOnCompletion != nil {
                cleanupTemporaryPendingShareUpload(cleanupOnCompletion)
                return false
            }
            return queueUserSelectedUploadForLater(url: url, filename: filename, mimeType: mimeType)
        }
        let tempId = "local-\(UUID().uuidString)"
        let access = url.startAccessingSecurityScopedResource()
        if access {
            securityScopedURLs[tempId] = url
        }
        let bookmarkData = makeBookmarkData(for: url)
        let sizeBytes = fileSizeBytes(for: url)
        let item = makeLocalItem(
            input: LocalIngestionItemInput(
                id: tempId,
                filename: filename,
                mimeType: mimeType,
                sizeBytes: sizeBytes,
                status: "uploading",
                stage: "uploading",
                progress: 0,
                sourceUrl: nil
            )
        )
        store.addLocalUpload(item, bookmarkData: bookmarkData)
        prepareSelection(fileId: tempId)

        uploadManager.startUpload(
            request: UploadRequest(
                uploadId: tempId,
                fileURL: url,
                filename: filename,
                mimeType: mimeType,
                folder: ""
            ),
            onProgress: { [weak self] progress in
                guard let self else { return }
                self.store.updateLocalUpload(
                    fileId: tempId,
                    status: "uploading",
                    stage: "uploading",
                    progress: progress
                )
            },
            onCompletion: { [weak self] result in
                guard let self else { return }
                Task { @MainActor in
                    await self.handleUploadCompletion(
                        tempId: tempId,
                        filename: filename,
                        mimeType: mimeType,
                        sizeBytes: sizeBytes,
                        result: result
                    )
                    self.cleanupTemporaryPendingShareUpload(cleanupOnCompletion)
                }
            }
        )
        return true
    }

    private func cleanupTemporaryPendingShareUpload(_ url: URL?) {
        guard let url else { return }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pending-share-uploads", isDirectory: true)
            .standardizedFileURL
        let directory = url.deletingLastPathComponent().standardizedFileURL
        guard directory.deletingLastPathComponent().path == root.path,
              UUID(uuidString: directory.lastPathComponent) != nil else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    private func queueUserSelectedUploadForLater(url: URL, filename: String, mimeType: String) -> Bool {
        let access = url.startAccessingSecurityScopedResource()
        defer {
            if access {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let queued = pendingShareStore.enqueueFile(
            at: url,
            filename: filename,
            mimeType: mimeType,
            kind: .file
        )
        if queued != nil {
            toastCenter.show(message: "Saved for later", style: .success)
        } else {
            toastCenter.show(message: "Could not save for later")
        }
        return queued != nil
    }
}
