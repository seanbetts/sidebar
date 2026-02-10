import UIKit
import OSLog
import sideBarShared
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    // Stored properties are intentionally module-scoped so extension files can share logic.
    var environment: ShareExtensionEnvironment?
    var progressView: ShareProgressView?
    let pendingShareStore = PendingShareStore.shared
    let logger = Logger(subsystem: "sideBar", category: "ShareExtension")

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

    func processSharedContent() {
        guard let itemProviders = sharedItemProviders() else {
            showError(ExtensionUserMessageCatalog.message(for: .invalidSharePayload))
            return
        }

        Task { [weak self] in
            guard let self else { return }
            if await self.handlePreferredContent(from: itemProviders) {
                return
            }
            await self.handleURLFallback(from: itemProviders)
        }
    }

    private func sharedItemProviders() -> [NSItemProvider]? {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            return nil
        }
        let itemProviders = extensionItems.flatMap { $0.attachments ?? [] }
        return itemProviders.isEmpty ? nil : itemProviders
    }

    private func handlePreferredContent(from itemProviders: [NSItemProvider]) async -> Bool {
        for itemProvider in itemProviders {
            if itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                await handleImage(itemProvider)
                return true
            }

            if itemProvider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                await handleFile(itemProvider, preferredType: .pdf)
                return true
            }

            if hasBinaryFileContent(itemProvider) {
                await handleFile(itemProvider, preferredType: .data)
                return true
            }
        }
        return false
    }

    private func hasBinaryFileContent(_ itemProvider: NSItemProvider) -> Bool {
        itemProvider.hasItemConformingToTypeIdentifier(UTType.data.identifier) &&
        !itemProvider.hasItemConformingToTypeIdentifier(UTType.url.identifier) &&
        !itemProvider.hasItemConformingToTypeIdentifier(UTType.text.identifier)
    }

    private func handleURLFallback(from itemProviders: [NSItemProvider]) async {
        var extractionError: Error?
        for itemProvider in itemProviders {
            do {
                if let url = try await extractURL(from: itemProvider) {
                    await MainActor.run { [weak self] in
                        self?.saveURL(url)
                    }
                    return
                }
            } catch {
                if extractionError == nil {
                    extractionError = error
                }
                logger.error(
                    "Failed to extract URL from shared content: \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        await MainActor.run { [weak self] in
            if let extractionError {
                self?.showError(ShareExtensionMessageMapper.errorMessage(for: extractionError))
                return
            }
            self?.showError(ExtensionUserMessageCatalog.message(for: .unsupportedContent))
        }
    }
}
