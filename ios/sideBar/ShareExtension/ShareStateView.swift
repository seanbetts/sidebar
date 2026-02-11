import UIKit

class ShareStateView: UIView {
    private enum Layout {
        static let cardCornerRadius: CGFloat = 20
        static let defaultSpacing: CGFloat = 12
        static let cardHorizontalPadding: CGFloat = 22
        static let cardVerticalPadding: CGFloat = 24
        static let contentHorizontalInset: CGFloat = 20
        static let contentVerticalInset: CGFloat = 16
        static let logoSize: CGFloat = 34
    }

    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let logoImageView = UIImageView()
    private let brandStack = UIStackView()

    init(
        message: String,
        accessoryView: UIView,
        spacingAfterTitle: CGFloat = Layout.defaultSpacing,
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
        backgroundColor = .systemGroupedBackground

        titleLabel.text = "sideBar"
        titleLabel.font = .systemFont(ofSize: 30, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center

        logoImageView.image = UIImage(named: "AppLogo", in: Bundle.main, compatibleWith: nil)
        logoImageView.isHidden = logoImageView.image == nil
        logoImageView.contentMode = .scaleAspectFit
        logoImageView.accessibilityIdentifier = "share-brand-logo"
        logoImageView.translatesAutoresizingMaskIntoConstraints = false
        logoImageView.heightAnchor.constraint(equalToConstant: Layout.logoSize).isActive = true
        logoImageView.widthAnchor.constraint(equalToConstant: Layout.logoSize).isActive = true

        messageLabel.text = message
        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

        brandStack.axis = .horizontal
        brandStack.alignment = .center
        brandStack.spacing = 10
        brandStack.addArrangedSubview(logoImageView)
        brandStack.addArrangedSubview(titleLabel)

        var arrangedSubviews: [UIView] = [brandStack, accessoryView, messageLabel]
        if let footerView {
            arrangedSubviews.append(footerView)
        }

        let content = UIStackView(arrangedSubviews: arrangedSubviews)
        content.axis = .vertical
        content.alignment = .center
        content.spacing = Layout.defaultSpacing
        if spacingAfterTitle != content.spacing {
            content.setCustomSpacing(spacingAfterTitle, after: brandStack)
        }
        if footerView != nil {
            content.setCustomSpacing(16, after: messageLabel)
        }
        content.isLayoutMarginsRelativeArrangement = true
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Layout.cardVerticalPadding,
            leading: Layout.cardHorizontalPadding,
            bottom: Layout.cardVerticalPadding,
            trailing: Layout.cardHorizontalPadding
        )
        content.backgroundColor = .secondarySystemBackground
        content.layer.cornerRadius = Layout.cardCornerRadius
        content.layer.cornerCurve = .continuous
        content.accessibilityIdentifier = "share-state-card"
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        NSLayoutConstraint.activate([
            content.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor),
            content.centerYAnchor.constraint(equalTo: safeAreaLayoutGuide.centerYAnchor),
            content.topAnchor.constraint(
                greaterThanOrEqualTo: safeAreaLayoutGuide.topAnchor,
                constant: Layout.contentVerticalInset
            ),
            content.bottomAnchor.constraint(
                lessThanOrEqualTo: safeAreaLayoutGuide.bottomAnchor,
                constant: -Layout.contentVerticalInset
            ),
            content.leadingAnchor.constraint(
                greaterThanOrEqualTo: safeAreaLayoutGuide.leadingAnchor,
                constant: Layout.contentHorizontalInset
            ),
            content.trailingAnchor.constraint(
                lessThanOrEqualTo: safeAreaLayoutGuide.trailingAnchor,
                constant: -Layout.contentHorizontalInset
            ),
            content.widthAnchor.constraint(lessThanOrEqualToConstant: 360)
        ])
    }
}
