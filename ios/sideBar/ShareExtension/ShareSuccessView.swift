import UIKit

final class ShareSuccessView: UIView {
    private let checkmarkImageView = UIImageView()
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

        checkmarkImageView.image = UIImage(systemName: "checkmark.circle.fill")
        checkmarkImageView.tintColor = .label
        checkmarkImageView.contentMode = .scaleAspectFit
        checkmarkImageView.heightAnchor.constraint(equalToConstant: 36).isActive = true
        checkmarkImageView.widthAnchor.constraint(equalToConstant: 36).isActive = true

        titleLabel.text = "sideBar"
        titleLabel.font = .systemFont(ofSize: 36, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center

        logoImageView.image = UIImage(named: "AppLogo", in: Bundle.main, compatibleWith: nil)
        logoImageView.contentMode = .scaleAspectFit
        logoImageView.heightAnchor.constraint(equalToConstant: 88).isActive = true
        logoImageView.widthAnchor.constraint(equalToConstant: 88).isActive = true

        messageLabel.text = message
        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

        let content = UIStackView(arrangedSubviews: [logoImageView, titleLabel, checkmarkImageView, messageLabel])
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
