import UIKit
import sideBarShared

extension ShareViewController {
    // MARK: - UI

    enum DismissDelay {
        static let value: TimeInterval = 1.2
    }

    func showError(_ message: String) {
        setContentView(ShareErrorView(message: message))
        DispatchQueue.main.asyncAfter(deadline: .now() + DismissDelay.value) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
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
}
