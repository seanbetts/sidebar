import UIKit

final class ShareErrorView: UIView {
    private let iconImageView = UIImageView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let logoImageView = UIImageView()

    init(message: String) {
        super.init(frame: .zero)
        setup(message: message)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup(message: String) {
        backgroundColor = .systemBackground

        iconImageView.image = UIImage(systemName: "xmark.circle.fill")
        iconImageView.tintColor = .label
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.heightAnchor.constraint(equalToConstant: 36).isActive = true
        iconImageView.widthAnchor.constraint(equalToConstant: 36).isActive = true

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

        let content = UIStackView(arrangedSubviews: [logoImageView, titleLabel, iconImageView, messageLabel])
        content.axis = .vertical
        content.alignment = .center
        content.spacing = 8
        content.setCustomSpacing(72, after: titleLabel)
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
