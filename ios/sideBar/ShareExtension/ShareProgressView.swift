import UIKit

final class ShareProgressView: ShareStateView {
    private let progressView = UIProgressView(progressViewStyle: .default)

    private(set) var progress: Float = 0

    init(message: String) {
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.progress = 0
        progressView.trackTintColor = .systemGray5
        progressView.progressTintColor = .systemBlue

        let progressContainer = UIView()
        progressContainer.translatesAutoresizingMaskIntoConstraints = false
        progressContainer.addSubview(progressView)
        NSLayoutConstraint.activate([
            progressView.leadingAnchor.constraint(equalTo: progressContainer.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: progressContainer.trailingAnchor),
            progressView.centerYAnchor.constraint(equalTo: progressContainer.centerYAnchor),
            progressContainer.widthAnchor.constraint(equalToConstant: 200),
            progressContainer.heightAnchor.constraint(equalToConstant: 44)
        ])

        super.init(message: message, accessoryView: progressContainer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateProgress(_ value: Float, message: String? = nil) {
        progress = value
        progressView.setProgress(value, animated: true)
        if let message {
            updateMessage(message)
        }
    }
}
