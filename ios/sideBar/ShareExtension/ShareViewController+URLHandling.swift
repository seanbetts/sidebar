import UIKit
import UniformTypeIdentifiers
import sideBarShared

extension ShareViewController {
    // MARK: - URL Handling

    func extractURL(from itemProvider: NSItemProvider) async -> URL? {
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

        for identifier in identifiersToTry where itemProvider.hasItemConformingToTypeIdentifier(identifier) {
            if let url = await loadURL(from: itemProvider, typeIdentifier: identifier) {
                return url
            }
        }
        return nil
    }

    func saveURL(_ url: URL) {
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
    func queuePendingWebsite(_ url: URL) {
        let item = ShareExtensionURLQueueHandler.enqueueURLForLater(
            url,
            pendingStore: pendingShareStore
        )
        showQueueResult(item)
    }

    @MainActor
    func queuePendingFile(data: Data, filename: String, mimeType: String, isImage: Bool) {
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
