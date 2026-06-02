import Foundation
import UniformTypeIdentifiers
import sideBarShared

extension ShareViewController {
    // MARK: - URL Handling

    func normalizedWebsiteEventURL(_ url: URL) -> String {
        ExtensionURLMessageHandler.normalizeQueuedURL(url.absoluteString) ?? url.absoluteString
    }

    func extractURL(from itemProvider: NSItemProvider) async throws -> URL? {
        let identifiersToTry = urlLoadCandidateIdentifiers(from: itemProvider)
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

    func extractWebsiteURL(from itemProvider: NSItemProvider) async throws -> URL? {
        let identifiersToTry = urlLoadCandidateIdentifiers(from: itemProvider)
        var loadError: Error?
        for identifier in identifiersToTry where itemProvider.hasItemConformingToTypeIdentifier(identifier) {
            do {
                if let url = try await loadURL(from: itemProvider, typeIdentifier: identifier),
                   ExtensionURLMessageHandler.normalizeQueuedURL(url.absoluteString) != nil {
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

    func urlLoadCandidateIdentifiers(from itemProvider: NSItemProvider) -> [String] {
        let urlTypes: [UTType] = [.url, .plainText, .text, .html, .propertyList]
        let candidateIdentifiers = itemProvider.registeredTypeIdentifiers.compactMap { identifier -> String? in
            guard let type = UTType(identifier) else { return nil }
            if type.conforms(to: .url)
                || type.conforms(to: .text)
                || type.conforms(to: .plainText)
                || type.conforms(to: .html)
                || type.conforms(to: .propertyList) {
                return identifier
            }
            return nil
        }
        return candidateIdentifiers.isEmpty
            ? urlTypes.map(\.identifier)
            : candidateIdentifiers
    }

    func saveURL(_ url: URL) {
        setContentView(ShareLoadingView(message: ExtensionUserMessageCatalog.message(for: .savingWebsite)))
        Task { @MainActor in
            await saveOrQueueWebsite(url)
        }
    }

    @MainActor
    func saveOrQueueWebsite(_ url: URL) async {
        let payload = await ExtensionURLMessageHandler.handleSaveURLMessage(
            action: "save_url",
            urlString: normalizedWebsiteEventURL(url),
            pendingStore: pendingShareStore,
            saveStrategy: .queueOnly
        )

        showSaveURLResult(payload)
    }

    @MainActor
    func queuePendingWebsite(_ url: URL, successCode: ExtensionMessageCode = .savedForLater) {
        guard pendingShareStore.canQueueURLItems() else {
            showError(ExtensionUserMessageCatalog.sharedStorageUnavailableMessage())
            return
        }
        let item = ShareExtensionURLQueueHandler.enqueueURLForLater(
            url,
            pendingStore: pendingShareStore
        )
        showQueueResult(item, successCode: successCode)
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
    func showQueueResult(_ item: PendingShareItem?, successCode: ExtensionMessageCode = .savedForLater) {
        let message = item == nil
            ? ShareExtensionMessageMapper.queueResultMessage(for: item)
            : ExtensionUserMessageCatalog.message(for: successCode)
        if ShareExtensionMessageMapper.queueSucceeded(for: item) {
            showSuccess(message: message)
            return
        }
        showError(message)
    }

    @MainActor
    func showSaveURLResult(_ payload: [String: Any]) {
        let ok = payload["ok"] as? Bool ?? false
        if ok {
            let message = payload["message"] as? String
                ?? ExtensionUserMessageCatalog.message(for: .savedForLater)
            showSuccess(message: message)
            return
        }

        let message = payload["error"] as? String
            ?? ExtensionUserMessageCatalog.message(for: .unknownFailure)
        showError(message)
    }
}
