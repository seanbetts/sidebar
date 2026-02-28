import Foundation
import UniformTypeIdentifiers
import sideBarShared

extension ShareViewController {
    // MARK: - URL Handling

    func normalizedWebsiteEventURL(_ url: URL) -> String {
        ExtensionURLMessageHandler.normalizeQueuedURL(url.absoluteString) ?? url.absoluteString
    }

    func extractURL(from itemProvider: NSItemProvider) async throws -> URL? {
        let urlTypes: [UTType] = [.url, .plainText, .text, .html]
        let candidateIdentifiers = itemProvider.registeredTypeIdentifiers.compactMap { identifier -> String? in
            guard let type = UTType(identifier) else { return nil }
            if type.conforms(to: .url)
                || type.conforms(to: .text)
                || type.conforms(to: .plainText)
                || type.conforms(to: .html) {
                return identifier
            }
            return nil
        }
        let identifiersToTry = candidateIdentifiers.isEmpty
            ? urlTypes.map(\.identifier)
            : candidateIdentifiers

        var loadError: Error?
        for identifier in identifiersToTry where itemProvider.hasItemConformingToTypeIdentifier(identifier) {
            do {
                if let url = try await loadURL(from: itemProvider, typeIdentifier: identifier) {
                    return url
                }
            } catch {
                if loadError == nil {
                    loadError = error
                }
            }
        }
        if let loadError {
            throw loadError
        }
        return nil
    }

    func saveURL(_ url: URL) {
        setContentView(ShareLoadingView(message: ExtensionUserMessageCatalog.message(for: .savingWebsite)))
        Task { @MainActor in
            queuePendingWebsite(url)
        }
    }

    @MainActor
    func queuePendingWebsite(_ url: URL) {
        guard pendingShareStore.canQueueURLItems() else {
            showError(ExtensionUserMessageCatalog.sharedStorageUnavailableMessage())
            return
        }
        let item = ShareExtensionURLQueueHandler.enqueueURLForLater(
            url,
            pendingStore: pendingShareStore
        )
        showQueueResult(item)
    }

    @MainActor
    func queuePendingFile(data: Data, filename: String, mimeType: String, isImage: Bool) {
        guard pendingShareStore.canQueueFileItems() else {
            showError(ExtensionUserMessageCatalog.sharedStorageUnavailableMessage())
            return
        }
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
    func queuePendingFile(at url: URL, filename: String, mimeType: String, isImage: Bool) {
        guard pendingShareStore.canQueueFileItems() else {
            showError(ExtensionUserMessageCatalog.sharedStorageUnavailableMessage())
            return
        }
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
    func showQueueResult(_ item: PendingShareItem?) {
        let message = ShareExtensionMessageMapper.queueResultMessage(for: item)
        if ShareExtensionMessageMapper.queueSucceeded(for: item) {
            showSuccess(message: message)
            return
        }
        showError(message)
    }
}
