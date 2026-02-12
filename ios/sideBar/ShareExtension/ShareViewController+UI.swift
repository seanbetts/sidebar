import UIKit
import sideBarShared

extension ShareViewController {
    // MARK: - UI

    enum DismissDelay {
        static let value: TimeInterval = 1.2
    }

    func showError(_ message: String) {
        setContentView(ShareErrorView(message: message))
    }

    func showSuccess(message: String) {
        setContentView(ShareSuccessView(message: message))
        DispatchQueue.main.asyncAfter(deadline: .now() + DismissDelay.value) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    func setContentView(_ content: UIView) {
        view.subviews.forEach { $0.removeFromSuperview() }
        if let stateView = content as? ShareStateView {
            view.backgroundColor = stateView.hostBackgroundColor
        } else {
            view.backgroundColor = .systemBackground
        }
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
}
