import UIKit
import UniformTypeIdentifiers
import sideBarShared

extension ShareViewController {
    // MARK: - Image Handling

    func handleImage(_ itemProvider: NSItemProvider) async {
        await MainActor.run { [weak self] in
            self?.setContentView(ShareLoadingView(message: ExtensionUserMessageCatalog.message(for: .preparingImage)))
        }

        let imageData: Data?
        let filename: String
        let mimeType: String

        let imageResult = await loadImageResult(from: itemProvider)
        if let image = imageResult.value {
            imageData = image.jpegData(compressionQuality: 0.9)
            filename = "shared_image_\(Int(Date().timeIntervalSince1970)).jpg"
            mimeType = "image/jpeg"
        } else {
            let dataResult = await loadDataResult(from: itemProvider, typeIdentifier: UTType.image.identifier)
            if let data = dataResult.value {
                imageData = data
                let suggestedName = itemProvider.suggestedName ?? "shared_image"
                filename = suggestedName.contains(".") ? suggestedName : "\(suggestedName).jpg"
                mimeType = mimeTypeForFilename(filename)
            } else {
                let sourceError = imageResult.error ?? dataResult.error
                await MainActor.run { [weak self] in
                    self?.showProviderLoadError(sourceError, fallback: .imageLoadFailed)
                }
                return
            }
        }

        guard let data = imageData else {
            await MainActor.run { [weak self] in
                self?.showError(ExtensionUserMessageCatalog.message(for: .imageProcessFailed))
            }
            return
        }

        if !(await ShareNetworkMonitor.isOnline()) {
            await MainActor.run {
                self.queuePendingFile(data: data, filename: filename, mimeType: mimeType, isImage: true)
            }
            return
        }

        await uploadFile(data: data, filename: filename, mimeType: mimeType, isImage: true)
    }

    func loadImageResult(from itemProvider: NSItemProvider) async -> ShareItemProviderLoadResult<UIImage> {
        await withCheckedContinuation { continuation in
            itemProvider.loadObject(ofClass: UIImage.self) { object, error in
                continuation.resume(
                    returning: ShareItemProviderLoadResult(
                        value: object as? UIImage,
                        error: error
                    )
                )
            }
        }
    }

    // MARK: - File Handling

    func handleFile(_ itemProvider: NSItemProvider, preferredType: UTType) async {
        await MainActor.run { [weak self] in
            self?.setContentView(ShareLoadingView(message: ExtensionUserMessageCatalog.message(for: .preparingFile)))
        }

        let typeIdentifier = preferredType.identifier
        let fileURLResult = await loadFileURLResult(from: itemProvider, typeIdentifier: typeIdentifier)
        if let fileURL = fileURLResult.value {
            let suggestedName = itemProvider.suggestedName ?? fileURL.lastPathComponent
            let filename = suggestedName.isEmpty ? fileURL.lastPathComponent : suggestedName
            let mimeType = mimeTypeForFilename(filename)
            if !(await ShareNetworkMonitor.isOnline()) {
                await MainActor.run { [weak self] in
                    self?.queuePendingFile(at: fileURL, filename: filename, mimeType: mimeType, isImage: false)
                }
                try? FileManager.default.removeItem(at: fileURL)
                return
            }
            await uploadFileFromURL(fileURL, itemProvider: itemProvider)
            return
        }

        let dataResult = await loadDataResult(from: itemProvider, typeIdentifier: typeIdentifier)
        guard let data = dataResult.value else {
            let sourceError = fileURLResult.error ?? dataResult.error
            await MainActor.run { [weak self] in
                self?.showProviderLoadError(sourceError, fallback: .fileLoadFailed)
            }
            return
        }

        let suggestedName = itemProvider.suggestedName ?? "shared_file"
        let filename: String
        if suggestedName.contains(".") {
            filename = suggestedName
        } else {
            let ext = preferredType == .pdf ? "pdf" : "bin"
            filename = "\(suggestedName).\(ext)"
        }
        let mimeType = mimeTypeForFilename(filename)

        if !(await ShareNetworkMonitor.isOnline()) {
            await MainActor.run { [weak self] in
                self?.queuePendingFile(data: data, filename: filename, mimeType: mimeType, isImage: false)
            }
            return
        }

        await uploadFile(data: data, filename: filename, mimeType: mimeType, isImage: false)
    }

    func loadFileURLResult(from itemProvider: NSItemProvider, typeIdentifier: String) async -> ShareItemProviderLoadResult<URL> {
        await withCheckedContinuation { continuation in
            itemProvider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, loadError in
                guard let url else {
                    continuation.resume(returning: ShareItemProviderLoadResult(value: nil, error: loadError))
                    return
                }
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(url.pathExtension)
                do {
                    try FileManager.default.copyItem(at: url, to: tempURL)
                    continuation.resume(returning: ShareItemProviderLoadResult(value: tempURL, error: nil))
                } catch {
                    continuation.resume(returning: ShareItemProviderLoadResult(value: nil, error: error))
                }
            }
        }
    }

    func uploadFileFromURL(_ fileURL: URL, itemProvider: NSItemProvider) async {
        let filename = itemProvider.suggestedName ?? fileURL.lastPathComponent
        let mimeType = mimeTypeForFilename(filename)
        await uploadFile(at: fileURL, filename: filename, mimeType: mimeType, isImage: false)
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Upload

    func uploadFile(data: Data, filename: String, mimeType: String, isImage: Bool) async {
        guard let environment else {
            await MainActor.run { [weak self] in
                self?.showError(ExtensionUserMessageCatalog.message(for: .notAuthenticated))
            }
            return
        }

        guard await environment.ensureValidAccessToken() else {
            await MainActor.run { [weak self] in
                self?.showError(ExtensionUserMessageCatalog.message(for: .notAuthenticated))
            }
            return
        }

        await MainActor.run { [weak self] in
            let progress = ShareProgressView(
                message: isImage
                    ? ExtensionUserMessageCatalog.message(for: .uploadingImage)
                    : ExtensionUserMessageCatalog.message(for: .uploadingFile)
            )
            self?.progressView = progress
            self?.setContentView(progress)
        }

        func uploadNow() async throws -> String {
            try await environment.uploadFile(
                data: data,
                filename: filename,
                mimeType: mimeType
            )
        }

        func handleSuccess(fileId: String) async {
            if isImage {
                ExtensionEventStore.shared.recordImageSaved(fileId: fileId, filename: filename)
            } else {
                ExtensionEventStore.shared.recordFileSaved(fileId: fileId, filename: filename)
            }
            await MainActor.run { [weak self] in
                self?.showSuccess(
                    message: isImage
                        ? ExtensionUserMessageCatalog.message(for: .imageSaved)
                        : ExtensionUserMessageCatalog.message(for: .fileSaved)
                )
            }
        }

        func handleFailure(_ error: Error) async {
            await MainActor.run { [weak self] in
                if self?.isOfflineError(error) == true {
                    self?.queuePendingFile(data: data, filename: filename, mimeType: mimeType, isImage: isImage)
                    return
                }
                if environment.isUnauthorized(error) {
                    self?.showError(ExtensionUserMessageCatalog.message(for: .notAuthenticated))
                    return
                }
                self?.showError(ShareExtensionMessageMapper.errorMessage(for: error))
            }
        }

        do {
            let fileId = try await uploadNow()
            await handleSuccess(fileId: fileId)
        } catch {
            if environment.isUnauthorized(error),
               await environment.ensureValidAccessToken(forceRefresh: true) {
                do {
                    let fileId = try await uploadNow()
                    await handleSuccess(fileId: fileId)
                    return
                } catch {
                    await handleFailure(error)
                    return
                }
            }
            await handleFailure(error)
        }
    }

    func uploadFile(at fileURL: URL, filename: String, mimeType: String, isImage: Bool) async {
        guard let environment else {
            await MainActor.run { [weak self] in
                self?.showError(ExtensionUserMessageCatalog.message(for: .notAuthenticated))
            }
            return
        }

        guard await environment.ensureValidAccessToken() else {
            await MainActor.run { [weak self] in
                self?.showError(ExtensionUserMessageCatalog.message(for: .notAuthenticated))
            }
            return
        }

        await MainActor.run { [weak self] in
            let progress = ShareProgressView(
                message: isImage
                    ? ExtensionUserMessageCatalog.message(for: .uploadingImage)
                    : ExtensionUserMessageCatalog.message(for: .uploadingFile)
            )
            self?.progressView = progress
            self?.setContentView(progress)
        }

        func uploadNow() async throws -> String {
            try await environment.uploadFile(
                fileURL: fileURL,
                filename: filename,
                mimeType: mimeType
            )
        }

        func handleSuccess(fileId: String) async {
            if isImage {
                ExtensionEventStore.shared.recordImageSaved(fileId: fileId, filename: filename)
            } else {
                ExtensionEventStore.shared.recordFileSaved(fileId: fileId, filename: filename)
            }
            await MainActor.run { [weak self] in
                self?.showSuccess(
                    message: isImage
                        ? ExtensionUserMessageCatalog.message(for: .imageSaved)
                        : ExtensionUserMessageCatalog.message(for: .fileSaved)
                )
            }
        }

        func handleFailure(_ error: Error) async {
            await MainActor.run { [weak self] in
                if self?.isOfflineError(error) == true {
                    self?.queuePendingFile(at: fileURL, filename: filename, mimeType: mimeType, isImage: isImage)
                    return
                }
                if environment.isUnauthorized(error) {
                    self?.showError(ExtensionUserMessageCatalog.message(for: .notAuthenticated))
                    return
                }
                self?.showError(ShareExtensionMessageMapper.errorMessage(for: error))
            }
        }

        do {
            let fileId = try await uploadNow()
            await handleSuccess(fileId: fileId)
        } catch {
            if environment.isUnauthorized(error),
               await environment.ensureValidAccessToken(forceRefresh: true) {
                do {
                    let fileId = try await uploadNow()
                    await handleSuccess(fileId: fileId)
                    return
                } catch {
                    await handleFailure(error)
                    return
                }
            }
            await handleFailure(error)
        }
    }
}
