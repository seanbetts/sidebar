import Foundation
import ImageIO
import UniformTypeIdentifiers
import sideBarShared

enum ShareExtensionPayloadSizePolicy {
    static let maxInMemoryPayloadBytes = 25 * 1024 * 1024

    static func acceptsInMemoryPayload(byteCount: Int) -> Bool {
        byteCount <= maxInMemoryPayloadBytes
    }
}

struct SharePreparedUploadFile {
    let fileURL: URL
    let filename: String
    let mimeType: String
}

enum ShareImageFilePreparer {
    static let maxUploadPixelSize = 2_048
    private static let compressionQuality = 0.86

    static func downsampledUploadImage(from sourceURL: URL, filename: String) -> SharePreparedUploadFile? {
        let sourceOptions = [
            kCGImageSourceShouldCache: false
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, sourceOptions),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, sourceOptions) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              max(width, height) > maxUploadPixelSize else {
            return nil
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxUploadPixelSize
        ] as CFDictionary
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }

        let preparedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("share-image-\(UUID().uuidString)")
            .appendingPathExtension("jpg")
        guard let destination = CGImageDestinationCreateWithURL(
            preparedURL as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        let destinationProperties = [
            kCGImageDestinationLossyCompressionQuality: compressionQuality
        ] as CFDictionary
        CGImageDestinationAddImage(destination, thumbnail, destinationProperties)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: preparedURL)
            return nil
        }

        return SharePreparedUploadFile(
            fileURL: preparedURL,
            filename: jpegFilename(for: filename),
            mimeType: "image/jpeg"
        )
    }

    private static func jpegFilename(for filename: String) -> String {
        let url = URL(fileURLWithPath: filename)
        let baseName = url.deletingPathExtension().lastPathComponent
        guard !baseName.isEmpty else {
            return "shared_image.jpg"
        }
        return "\(baseName).jpg"
    }
}

extension ShareViewController {
    // MARK: - Image Handling

    func handleImage(_ itemProvider: NSItemProvider) async {
        await MainActor.run { [weak self] in
            self?.setContentView(ShareLoadingView(message: ExtensionUserMessageCatalog.message(for: .preparingImage)))
        }

        let imageData: Data?
        let filename: String
        let mimeType: String

        let fileURLResult = await loadFileURLResult(from: itemProvider, typeIdentifier: UTType.image.identifier)
        if let fileURL = fileURLResult.value {
            await uploadFileFromURL(fileURL, itemProvider: itemProvider, isImage: true)
            return
        }

        let imageResult = await loadImageResult(from: itemProvider)
        if let image = imageResult.value,
           let encodedImageData = shareJPEGData(from: image, compressionQuality: 0.9) {
            imageData = encodedImageData
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
                let sourceError = fileURLResult.error ?? imageResult.error ?? dataResult.error
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
        guard ShareExtensionPayloadSizePolicy.acceptsInMemoryPayload(byteCount: data.count) else {
            await MainActor.run { [weak self] in
                self?.showError(ExtensionUserMessageCatalog.message(for: .sharedPayloadTooLarge))
            }
            return
        }

        await uploadFile(data: data, filename: filename, mimeType: mimeType, isImage: true)
    }

    func loadImageResult(from itemProvider: NSItemProvider) async -> ShareItemProviderLoadResult<SharePlatformImage> {
        await withCheckedContinuation { continuation in
            itemProvider.loadObject(ofClass: SharePlatformImage.self) { object, error in
                continuation.resume(
                    returning: ShareItemProviderLoadResult(
                        value: object as? SharePlatformImage,
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
        guard ShareExtensionPayloadSizePolicy.acceptsInMemoryPayload(byteCount: data.count) else {
            await MainActor.run { [weak self] in
                self?.showError(ExtensionUserMessageCatalog.message(for: .sharedPayloadTooLarge))
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

    func uploadFileFromURL(_ fileURL: URL, itemProvider: NSItemProvider, isImage: Bool = false) async {
        let filename = filenameForSharedFileURL(
            fileURL,
            itemProvider: itemProvider,
            fallbackExtension: isImage ? "jpg" : "bin"
        )
        let preparedImage = isImage
            ? ShareImageFilePreparer.downsampledUploadImage(from: fileURL, filename: filename)
            : nil
        let uploadURL = preparedImage?.fileURL ?? fileURL
        let uploadFilename = preparedImage?.filename ?? filename
        let mimeType = preparedImage?.mimeType ?? mimeTypeForFilename(filename)
        await uploadFile(at: uploadURL, filename: uploadFilename, mimeType: mimeType, isImage: isImage)
        if preparedImage != nil {
            try? FileManager.default.removeItem(at: uploadURL)
        }
        try? FileManager.default.removeItem(at: fileURL)
    }

    func filenameForSharedFileURL(
        _ fileURL: URL,
        itemProvider: NSItemProvider,
        fallbackExtension: String
    ) -> String {
        let fallbackName = fileURL.lastPathComponent.isEmpty ? "shared_file" : fileURL.lastPathComponent
        let suggestedName = itemProvider.suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let suggestedName, !suggestedName.isEmpty else {
            return fallbackName
        }
        guard !suggestedName.contains(".") else {
            return suggestedName
        }

        let fileExtension = fileURL.pathExtension.isEmpty ? fallbackExtension : fileURL.pathExtension
        guard !fileExtension.isEmpty else {
            return suggestedName
        }
        return "\(suggestedName).\(fileExtension)"
    }

    // MARK: - Upload

    func uploadFile(data: Data, filename: String, mimeType: String, isImage: Bool) async {
        guard ShareExtensionPayloadSizePolicy.acceptsInMemoryPayload(byteCount: data.count) else {
            await MainActor.run { [weak self] in
                self?.showError(ExtensionUserMessageCatalog.message(for: .sharedPayloadTooLarge))
            }
            return
        }

        guard let environment else {
            await MainActor.run { [weak self] in
                self?.queuePendingFile(data: data, filename: filename, mimeType: mimeType, isImage: isImage)
            }
            return
        }

        guard await environment.ensureValidAccessToken() else {
            await MainActor.run { [weak self] in
                self?.queuePendingFile(data: data, filename: filename, mimeType: mimeType, isImage: isImage)
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
            let classifiedError = environment.classifyUploadError(error)
            await MainActor.run { [weak self] in
                if classifiedError.retryability.allowsOfflineHandoff {
                    self?.queuePendingFile(data: data, filename: filename, mimeType: mimeType, isImage: isImage)
                    return
                }
                self?.showError(ShareExtensionMessageMapper.errorMessage(for: classifiedError))
            }
        }

        do {
            let fileId = try await uploadNow()
            await handleSuccess(fileId: fileId)
        } catch {
            if environment.shouldRetryUploadAfterAuthFailure(error),
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
                self?.queuePendingFile(at: fileURL, filename: filename, mimeType: mimeType, isImage: isImage)
            }
            return
        }

        guard await environment.ensureValidAccessToken() else {
            await MainActor.run { [weak self] in
                self?.queuePendingFile(at: fileURL, filename: filename, mimeType: mimeType, isImage: isImage)
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
            let classifiedError = environment.classifyUploadError(error)
            await MainActor.run { [weak self] in
                if classifiedError.retryability.allowsOfflineHandoff {
                    self?.queuePendingFile(at: fileURL, filename: filename, mimeType: mimeType, isImage: isImage)
                    return
                }
                self?.showError(ShareExtensionMessageMapper.errorMessage(for: classifiedError))
            }
        }

        do {
            let fileId = try await uploadNow()
            await handleSuccess(fileId: fileId)
        } catch {
            if environment.shouldRetryUploadAfterAuthFailure(error),
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
