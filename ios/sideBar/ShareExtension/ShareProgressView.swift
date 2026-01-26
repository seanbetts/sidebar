import UIKit

final class ShareProgressView: UIView {
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let logoImageView = UIImageView()

    private(set) var progress: Float = 0

    init(message: String) {
        super.init(frame: .zero)
        setup(message: message)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateProgress(_ value: Float, message: String? = nil) {
        progress = value
        progressView.setProgress(value, animated: true)
        if let message {
            messageLabel.text = message
        }
    }

    private func setup(message: String) {
        backgroundColor = .systemBackground

        titleLabel.text = "sideBar"
        titleLabel.font = .systemFont(ofSize: 36, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center

        logoImageView.image = UIImage(named: "AppLogo", in: Bundle.main, compatibleWith: nil)
        if logoImageView.image == nil {
            logoImageView.image = UIImage(systemName: "app")
            logoImageView.tintColor = .label
        }
        logoImageView.contentMode = .scaleAspectFit
        logoImageView.translatesAutoresizingMaskIntoConstraints = false
        logoImageView.heightAnchor.constraint(equalToConstant: 88).isActive = true
        logoImageView.widthAnchor.constraint(equalToConstant: 88).isActive = true

        messageLabel.text = message
        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

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

        let content = UIStackView(arrangedSubviews: [logoImageView, titleLabel, progressContainer, messageLabel])
        content.axis = .vertical
        content.alignment = .center
        content.spacing = 8
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        NSLayoutConstraint.activate([
            content.centerXAnchor.constraint(equalTo: centerXAnchor),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
            content.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24)
        ])
    }
}
