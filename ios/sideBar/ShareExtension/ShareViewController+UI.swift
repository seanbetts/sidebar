import UIKit
import sideBarShared

extension ShareViewController {
    // MARK: - UI

    enum DismissDelay {
        static let value: TimeInterval = 1.2
    }

    func showError(_ message: String, retryAction: (() -> Void)? = nil) {
        let notAuthenticatedMessage = ExtensionUserMessageCatalog.message(for: .notAuthenticated)
        let storageMessage = ExtensionUserMessageCatalog.sharedStorageUnavailableMessage()
        let shouldShowOpenApp = message == notAuthenticatedMessage || message == storageMessage
        let effectiveRetry = retryAction ?? { [weak self] in
            self?.processSharedContent()
        }
        let errorView = ShareErrorView(
            message: message,
            retryAction: effectiveRetry,
            openAppAction: shouldShowOpenApp ? { [weak self] in
                self?.openMainApp()
            } : nil,
            closeAction: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
        )
        setContentView(errorView)
    }

    func showSuccess(message: String) {
        setContentView(ShareSuccessView(message: message))
        DispatchQueue.main.asyncAfter(deadline: .now() + DismissDelay.value) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    func setContentView(_ content: UIView) {
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

    func isOfflineError(_ error: Error) -> Bool {
        ExtensionNetworkErrorClassifier.isOfflineLike(error)
    }

    func showProviderLoadError(_ error: Error?, fallback: ExtensionMessageCode) {
        guard let error else {
            showError(ExtensionUserMessageCatalog.message(for: fallback))
            return
        }
        let mapped = ShareExtensionMessageMapper.errorMessage(for: error)
        if mapped == ExtensionUserMessageCatalog.message(for: .unknownFailure) {
            showError(ExtensionUserMessageCatalog.message(for: fallback))
            return
        }
        showError(mapped)
    }

    func openMainApp() {
        guard let url = URL(string: "sidebar://") else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }
        extensionContext?.open(url) { [weak self] success in
            if success {
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
        }
    }
}
