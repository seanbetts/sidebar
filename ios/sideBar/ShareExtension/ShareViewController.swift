import UIKit
import sideBarShared
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    // Stored properties are intentionally module-scoped so extension files can share logic.
    var environment: ShareExtensionEnvironment?
    var progressView: ShareProgressView?
    let pendingShareStore = PendingShareStore.shared

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
}
