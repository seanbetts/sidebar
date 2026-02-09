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

        if let image = await loadImage(from: itemProvider) {
            imageData = image.jpegData(compressionQuality: 0.9)
            filename = "shared_image_\(Int(Date().timeIntervalSince1970)).jpg"
            mimeType = "image/jpeg"
        } else if let data = await loadData(from: itemProvider, typeIdentifier: UTType.image.identifier) {
            imageData = data
            let suggestedName = itemProvider.suggestedName ?? "shared_image"
            filename = suggestedName.contains(".") ? suggestedName : "\(suggestedName).jpg"
            mimeType = mimeTypeForFilename(filename)
        } else {
            await MainActor.run { [weak self] in
                self?.showError(ExtensionUserMessageCatalog.message(for: .imageLoadFailed))
            }
            return
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

    func loadImage(from itemProvider: NSItemProvider) async -> UIImage? {
        await withCheckedContinuation { continuation in
            itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                continuation.resume(returning: object as? UIImage)
            }
        }
    }

    // MARK: - File Handling

    func handleFile(_ itemProvider: NSItemProvider, preferredType: UTType) async {
        await MainActor.run { [weak self] in
            self?.setContentView(ShareLoadingView(message: ExtensionUserMessageCatalog.message(for: .preparingFile)))
        }

        let typeIdentifier = preferredType.identifier
        if let fileURL = await loadFileURL(from: itemProvider, typeIdentifier: typeIdentifier) {
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

        guard let data = await loadData(from: itemProvider, typeIdentifier: typeIdentifier) else {
            await MainActor.run { [weak self] in
                self?.showError(ExtensionUserMessageCatalog.message(for: .fileLoadFailed))
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

    func loadFileURL(from itemProvider: NSItemProvider, typeIdentifier: String) async -> URL? {
        await withCheckedContinuation { continuation in
            itemProvider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(url.pathExtension)
                do {
                    try FileManager.default.copyItem(at: url, to: tempURL)
                    continuation.resume(returning: tempURL)
                } catch {
                    continuation.resume(returning: nil)
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

        await MainActor.run { [weak self] in
            let progress = ShareProgressView(
                message: isImage
                    ? ExtensionUserMessageCatalog.message(for: .uploadingImage)
                    : ExtensionUserMessageCatalog.message(for: .uploadingFile)
            )
            self?.progressView = progress
            self?.setContentView(progress)
        }

        do {
            let fileId = try await environment.uploadFile(
                data: data,
                filename: filename,
                mimeType: mimeType
            )
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
        } catch {
            await MainActor.run { [weak self] in
                if self?.isOfflineError(error) == true {
                    self?.queuePendingFile(data: data, filename: filename, mimeType: mimeType, isImage: isImage)
                    return
                }
                self?.showError(ShareExtensionMessageMapper.errorMessage(for: error))
            }
        }
    }

    func uploadFile(at fileURL: URL, filename: String, mimeType: String, isImage: Bool) async {
        guard let environment else {
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

        do {
            let fileId = try await environment.uploadFile(
                fileURL: fileURL,
                filename: filename,
                mimeType: mimeType
            )
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
        } catch {
            await MainActor.run { [weak self] in
                if self?.isOfflineError(error) == true {
                    self?.queuePendingFile(at: fileURL, filename: filename, mimeType: mimeType, isImage: isImage)
                    return
                }
                self?.showError(ShareExtensionMessageMapper.errorMessage(for: error))
            }
        }
    }
}
