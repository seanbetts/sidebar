import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import OSLog
import sideBarShared
import UniformTypeIdentifiers

final class ShareViewController: SharePlatformViewController {
    // Stored properties are intentionally module-scoped so extension files can share logic.
    var environment: ShareExtensionEnvironment?
    var environmentInitializationError: Error?
    var progressView: ShareProgressView?
    let pendingShareStore = PendingShareStore.shared
    let logger = Logger(subsystem: "sideBar", category: "ShareExtension")

    override func viewDidLoad() {
        super.viewDidLoad()
        shareApplyDefaultHostBackground(to: view)
        do {
            environment = try ShareExtensionEnvironment()
        } catch {
            environmentInitializationError = error
            logger.notice(
                "Share extension environment unavailable; falling back to queue-only mode: \(error.localizedDescription, privacy: .public)"
            )
            ShareExtensionDiagnostics.reporter.captureFailure(
                surface: "share_extension",
                stage: "environment_init_failed",
                message: "Share extension environment unavailable.",
                metadata: [
                    "reason": error.localizedDescription
                ]
            )
        }
        processSharedContent()
    }

    // MARK: - Content Processing

    func processSharedContent() {
        let itemProviders = sharedItemProviders()
        recordEntryDiagnostics(itemProviderCount: itemProviders?.count ?? 0)

        guard let itemProviders else {
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

    private func recordEntryDiagnostics(itemProviderCount: Int) {
        ShareExtensionDiagnostics.reporter.recordBreadcrumb(
            surface: "share_extension",
            stage: "begin_request",
            message: "Began processing shared content.",
            metadata: [
                "item_provider_count": "\(itemProviderCount)"
            ]
        )
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

    func hasBinaryFileContent(_ itemProvider: NSItemProvider) -> Bool {
        itemProvider.hasItemConformingToTypeIdentifier(UTType.data.identifier) &&
        !hasWebsiteLikeContent(itemProvider)
    }

    private func hasWebsiteLikeContent(_ itemProvider: NSItemProvider) -> Bool {
        itemProvider.hasItemConformingToTypeIdentifier(UTType.url.identifier) ||
        itemProvider.hasItemConformingToTypeIdentifier(UTType.text.identifier) ||
        itemProvider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) ||
        itemProvider.hasItemConformingToTypeIdentifier(UTType.html.identifier) ||
        itemProvider.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier)
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
