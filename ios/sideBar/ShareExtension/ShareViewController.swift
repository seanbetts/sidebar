import UIKit
import sideBarShared
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private var environment: ShareExtensionEnvironment?
    private var progressView: ShareProgressView?
    private let pendingShareStore = PendingShareStore.shared

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        do {
            environment = try ShareExtensionEnvironment()
        } catch {
            showError(ShareExtensionMessageMapper.errorMessage(for: error))
            return
        }
        processSharedContent()
    }

    // MARK: - Content Processing

    private func processSharedContent() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            showError(ExtensionUserMessageCatalog.message(for: .invalidSharePayload))
            return
        }

        let itemProviders = extensionItems.flatMap { $0.attachments ?? [] }
        guard !itemProviders.isEmpty else {
            showError(ExtensionUserMessageCatalog.message(for: .invalidSharePayload))
            return
        }

        Task { [weak self] in
            guard let self else { return }

            // Try to find content in priority order: images, files, URLs
            for itemProvider in itemProviders {
                // Check for images first
                if itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    await self.handleImage(itemProvider)
                    return
                }

                // Check for PDFs
                if itemProvider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                    await self.handleFile(itemProvider, preferredType: .pdf)
                    return
                }

                // Check for other file types
                if itemProvider.hasItemConformingToTypeIdentifier(UTType.data.identifier) &&
                   !itemProvider.hasItemConformingToTypeIdentifier(UTType.url.identifier) &&
                   !itemProvider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                    await self.handleFile(itemProvider, preferredType: .data)
                    return
                }
            }

            // Fall back to URL extraction
            for itemProvider in itemProviders {
                if let url = await self.extractURL(from: itemProvider) {
                    await MainActor.run { [weak self] in
                        self?.saveURL(url)
                    }
                    return
                }
            }

            await MainActor.run { [weak self] in
                self?.showError(ExtensionUserMessageCatalog.message(for: .unsupportedContent))
            }
        }
    }

    // MARK: - Image Handling

    private func handleImage(_ itemProvider: NSItemProvider) async {
        await MainActor.run { [weak self] in
            self?.setContentView(ShareLoadingView(message: ExtensionUserMessageCatalog.message(for: .preparingImage)))
        }

        // Try to load as UIImage first for better format handling
        let imageData: Data?
        let filename: String
        let mimeType: String

        if let image = await loadImage(from: itemProvider) {
            // Convert to JPEG for consistent handling
            imageData = image.jpegData(compressionQuality: 0.9)
            filename = "shared_image_\(Int(Date().timeIntervalSince1970)).jpg"
            mimeType = "image/jpeg"
        } else if let data = await loadData(from: itemProvider, typeIdentifier: UTType.image.identifier) {
            // Use raw data if UIImage loading fails
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

    private func loadImage(from itemProvider: NSItemProvider) async -> UIImage? {
        await withCheckedContinuation { continuation in
            itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                continuation.resume(returning: object as? UIImage)
            }
        }
    }

    // MARK: - File Handling

    private func handleFile(_ itemProvider: NSItemProvider, preferredType: UTType) async {
        await MainActor.run { [weak self] in
            self?.setContentView(ShareLoadingView(message: ExtensionUserMessageCatalog.message(for: .preparingFile)))
        }

        let typeIdentifier = preferredType.identifier

        // Try to get file URL first (for larger files)
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

        // Fall back to loading data directly
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

    private func loadFileURL(from itemProvider: NSItemProvider, typeIdentifier: String) async -> URL? {
        await withCheckedContinuation { continuation in
            itemProvider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _ in
                // Copy the file since the original will be deleted after this callback
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

    private func uploadFileFromURL(_ fileURL: URL, itemProvider: NSItemProvider) async {
        do {
            let data = try Data(contentsOf: fileURL)
            let filename = itemProvider.suggestedName ?? fileURL.lastPathComponent
            let mimeType = mimeTypeForFilename(filename)
            await uploadFile(data: data, filename: filename, mimeType: mimeType, isImage: false)
            try? FileManager.default.removeItem(at: fileURL)
        } catch {
            await MainActor.run { [weak self] in
                self?.showError(ExtensionUserMessageCatalog.message(for: .fileReadFailed))
            }
        }
    }

    // MARK: - Upload

    private func uploadFile(data: Data, filename: String, mimeType: String, isImage: Bool) async {
        guard let environment else {
            await MainActor.run { [weak self] in
                self?.showError(ExtensionUserMessageCatalog.message(for: .notAuthenticated))
            }
            return
        }

        await MainActor.run { [weak self] in
            let progressView = ShareProgressView(
                message: isImage
                    ? ExtensionUserMessageCatalog.message(for: .uploadingImage)
                    : ExtensionUserMessageCatalog.message(for: .uploadingFile)
            )
            self?.progressView = progressView
            self?.setContentView(progressView)
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

    // MARK: - URL Handling

    private func extractURL(from itemProvider: NSItemProvider) async -> URL? {
        let urlTypes: [UTType] = [.url, .plainText, .text, .html]
        let candidateIdentifiers = itemProvider.registeredTypeIdentifiers.compactMap { identifier -> String? in
            guard let type = UTType(identifier) else { return nil }
            if type.conforms(to: .url) || type.conforms(to: .text) ||
               type.conforms(to: .plainText) || type.conforms(to: .html) {
                return identifier
            }
            return nil
        }
        let identifiersToTry = candidateIdentifiers.isEmpty
            ? urlTypes.map(\.identifier)
            : candidateIdentifiers

        for identifier in identifiersToTry where itemProvider.hasItemConformingToTypeIdentifier(identifier) {
            if let url = await loadURL(from: itemProvider, typeIdentifier: identifier) {
                return url
            }
        }
        return nil
    }

    private func saveURL(_ url: URL) {
        guard let environment else {
            showError(ExtensionUserMessageCatalog.message(for: .notAuthenticated))
            return
        }
        setContentView(ShareLoadingView(message: ExtensionUserMessageCatalog.message(for: .savingWebsite)))
        Task { @MainActor in
            if !(await ShareNetworkMonitor.isOnline()) {
                queuePendingWebsite(url)
                return
            }
            do {
                _ = try await environment.websitesAPI.quickSave(url: url.absoluteString, title: nil)
                ExtensionEventStore.shared.recordWebsiteSaved(url: url.absoluteString)
                showSuccess(message: ExtensionUserMessageCatalog.message(for: .websiteSaved))
            } catch {
                if isOfflineError(error) {
                    queuePendingWebsite(url)
                } else {
                    showError(ShareExtensionMessageMapper.errorMessage(for: error))
                }
            }
        }
    }

    @MainActor
    private func queuePendingWebsite(_ url: URL) {
        let item = ShareExtensionURLQueueHandler.enqueueURLForLater(
            url,
            pendingStore: pendingShareStore
        )
        showQueueResult(item)
    }

    @MainActor
    private func queuePendingFile(data: Data, filename: String, mimeType: String, isImage: Bool) {
        let kind: PendingShareKind = isImage ? .image : .file
        let item = pendingShareStore.enqueueFile(
            data: data,
            filename: filename,
            mimeType: mimeType,
            kind: kind
        )
        showQueueResult(item)
    }

    @MainActor
    private func queuePendingFile(at url: URL, filename: String, mimeType: String, isImage: Bool) {
        let kind: PendingShareKind = isImage ? .image : .file
        let item = pendingShareStore.enqueueFile(
            at: url,
            filename: filename,
            mimeType: mimeType,
            kind: kind
        )
        showQueueResult(item)
    }

    @MainActor
    private func showQueueResult(_ item: PendingShareItem?) {
        let message = ShareExtensionMessageMapper.queueResultMessage(for: item)
        if ShareExtensionMessageMapper.queueSucceeded(for: item) {
            showSuccess(message: message)
            return
        }
        showError(message)
    }

    // MARK: - UI

    private enum DismissDelay {
        static let value: TimeInterval = 1.2
    }

    private func showError(_ message: String) {
        setContentView(ShareErrorView(message: message))
        DispatchQueue.main.asyncAfter(deadline: .now() + DismissDelay.value) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func showSuccess(message: String) {
        setContentView(ShareSuccessView(message: message))
        DispatchQueue.main.asyncAfter(deadline: .now() + DismissDelay.value) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func setContentView(_ content: UIView) {
        view.subviews.forEach { $0.removeFromSuperview() }
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: view.topAnchor),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func isOfflineError(_ error: Error) -> Bool {
        ExtensionNetworkErrorClassifier.isOfflineLike(error)
    }

    // MARK: - URL Parsing Helpers

    private func loadURL(from itemProvider: NSItemProvider, typeIdentifier: String) async -> URL? {
        if let item = await loadItem(from: itemProvider, typeIdentifier: typeIdentifier),
           let url = urlFromTextPayload(item) {
            return url
        }
        if let data = await loadData(from: itemProvider, typeIdentifier: typeIdentifier),
           let url = urlFromTextPayload(data) {
            return url
        }
        return nil
    }

    private func urlFromTextPayload(_ item: Any?) -> URL? {
        if let url = item as? URL {
            if url.isFileURL, let fileURL = extractURLFromFile(url) {
                return fileURL
            }
            return url
        }
        if let attributed = item as? NSAttributedString {
            if let url = extractFirstLink(from: attributed) {
                return url
            }
            return extractFirstURL(from: attributed.string)
        }
        if let string = item as? String {
            return extractFirstURL(from: string)
        }
        if let string = item as? NSString {
            return extractFirstURL(from: string as String)
        }
        if let data = item as? Data,
           let string = String(data: data, encoding: .utf8) {
            return extractFirstURL(from: string)
        }
        return nil
    }

    private func extractFirstLink(from attributed: NSAttributedString) -> URL? {
        var found: URL?
        let range = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttribute(.link, in: range, options: []) { value, _, stop in
            if let url = value as? URL {
                found = url
                stop.pointee = true
            } else if let string = value as? String, let url = URL(string: string) {
                found = url
                stop.pointee = true
            }
        }
        return found
    }

    private func extractFirstURL(from text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = detector.firstMatch(in: text, options: [], range: range),
              let url = match.url else {
            return nil
        }
        return url
    }

    private func extractURLFromFile(_ url: URL) -> URL? {
        guard let string = readTextFile(url) else { return nil }
        return extractFirstURL(from: string)
    }

    private func readTextFile(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let maxBytes = 64 * 1024
        let limitedData = data.count > maxBytes ? data.prefix(maxBytes) : data
        return String(data: limitedData, encoding: .utf8)
    }

    // MARK: - Item Loading Helpers

    private func loadItem(from itemProvider: NSItemProvider, typeIdentifier: String) async -> Any? {
        await withCheckedContinuation { continuation in
            itemProvider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                continuation.resume(returning: item)
            }
        }
    }

    private func loadData(from itemProvider: NSItemProvider, typeIdentifier: String) async -> Data? {
        await withCheckedContinuation { continuation in
            itemProvider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    // MARK: - MIME Type Helper

    private func mimeTypeForFilename(_ filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        let mappings: [String: String] = [
            "doc": "application/msword",
            "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "gif": "image/gif",
            "heic": "image/heic",
            "heif": "image/heic",
            "htm": "text/html",
            "html": "text/html",
            "jpeg": "image/jpeg",
            "jpg": "image/jpeg",
            "json": "application/json",
            "mov": "video/quicktime",
            "mp3": "audio/mpeg",
            "mp4": "video/mp4",
            "pdf": "application/pdf",
            "png": "image/png",
            "ppt": "application/vnd.ms-powerpoint",
            "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
            "txt": "text/plain",
            "webp": "image/webp",
            "xls": "application/vnd.ms-excel",
            "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "xml": "application/xml",
            "zip": "application/zip"
        ]
        return mappings[ext] ?? "application/octet-stream"
    }
}
