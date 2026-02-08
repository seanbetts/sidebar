import UIKit

final class ShareLoadingView: ShareStateView {
    init(message: String) {
        let activityIndicator = UIActivityIndicatorView(style: .large)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.startAnimating()
        super.init(message: message, accessoryView: activityIndicator)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
