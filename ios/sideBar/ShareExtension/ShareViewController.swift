import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private var environment: ShareExtensionEnvironment?

    override func viewDidLoad() {
        super.viewDidLoad()
        view = ShareLoadingView(message: "Saving website...")
        do {
            environment = try ShareExtensionEnvironment()
        } catch {
            showError(error.localizedDescription)
            return
        }
        extractSharedURL()
    }

    private func extractSharedURL() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let itemProvider = extensionItem.attachments?.first else {
            showError(ShareExtensionError.invalidSharePayload.localizedDescription)
            return
        }

        if itemProvider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            itemProvider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] item, error in
                DispatchQueue.main.async {
                    if let error {
                        self?.showError("Failed to read URL: \(error.localizedDescription)")
                        return
                    }
                    guard let url = item as? URL else {
                        self?.showError(ShareExtensionError.invalidSharePayload.localizedDescription)
                        return
                    }
                    self?.saveURL(url)
                }
            }
        } else {
            showError(ShareExtensionError.invalidSharePayload.localizedDescription)
        }
    }

    private func saveURL(_ url: URL) {
        guard let environment else {
            showError(ShareExtensionError.notAuthenticated.localizedDescription)
            return
        }
        Task { @MainActor in
            do {
                _ = try await environment.websitesAPI.quickSave(url: url.absoluteString, title: nil)
                ExtensionEventStore.shared.recordWebsiteSaved(url: url.absoluteString)
                showSuccess()
            } catch {
                showError(error.localizedDescription)
            }
        }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(
            title: "Unable to Save Website",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        present(alert, animated: true)
    }

    private func showSuccess() {
        view = ShareSuccessView(message: "Website saved")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
