import UIKit

class ShareStateView: UIView {
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let logoImageView = UIImageView()

    init(
        message: String,
        accessoryView: UIView,
        spacingAfterTitle: CGFloat = 8,
        footerView: UIView? = nil
    ) {
        super.init(frame: .zero)
        setup(
            message: message,
            accessoryView: accessoryView,
            spacingAfterTitle: spacingAfterTitle,
            footerView: footerView
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateMessage(_ message: String) {
        messageLabel.text = message
    }

    private func setup(
        message: String,
        accessoryView: UIView,
        spacingAfterTitle: CGFloat,
        footerView: UIView?
    ) {
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

        var arrangedSubviews: [UIView] = [logoImageView, titleLabel, accessoryView, messageLabel]
        if let footerView {
            arrangedSubviews.append(footerView)
        }

        let content = UIStackView(arrangedSubviews: arrangedSubviews)
        content.axis = .vertical
        content.alignment = .center
        content.spacing = 8
        if spacingAfterTitle != content.spacing {
            content.setCustomSpacing(spacingAfterTitle, after: titleLabel)
        }
        if footerView != nil {
            content.setCustomSpacing(20, after: messageLabel)
        }
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
