import UIKit

class ShareStateView: UIView {
    enum Style {
        case card
        case minimal
    }

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
    private let style: Style

    init(
        message: String,
        accessoryView: UIView,
        spacingAfterTitle: CGFloat = Layout.defaultSpacing,
        footerView: UIView? = nil,
        style: Style = .card
    ) {
        self.style = style
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

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            refreshBrandLogo()
        }
    }

    func updateMessage(_ message: String) {
        messageLabel.text = message
    }

    private func refreshBrandLogo() {
        logoImageView.image = brandLogoImage()
        logoImageView.isHidden = logoImageView.image == nil
    }

    private func brandLogoImage() -> UIImage? {
        let preferredName = traitCollection.userInterfaceStyle == .dark ? "logo-dark" : "logo-light"
        if let image = UIImage(named: preferredName, in: Bundle.main, compatibleWith: traitCollection) {
            return image
        }
        return UIImage(named: "AppLogo", in: Bundle.main, compatibleWith: traitCollection)
    }

    private func setup(
        message: String,
        accessoryView: UIView,
        spacingAfterTitle: CGFloat,
        footerView: UIView?
    ) {
        backgroundColor = .systemGroupedBackground

        titleLabel.text = "sideBar"
        titleLabel.font = .systemFont(ofSize: style == .minimal ? 28 : 30, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center

        refreshBrandLogo()
        logoImageView.contentMode = .scaleAspectFit
        logoImageView.accessibilityIdentifier = "share-brand-logo"
        logoImageView.translatesAutoresizingMaskIntoConstraints = false
        logoImageView.heightAnchor.constraint(equalToConstant: Layout.logoSize).isActive = true
        logoImageView.widthAnchor.constraint(equalToConstant: Layout.logoSize).isActive = true

        messageLabel.text = message
        messageLabel.font = style == .minimal
            ? .systemFont(ofSize: 15, weight: .regular)
            : .preferredFont(forTextStyle: .subheadline)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

        brandStack.axis = style == .minimal ? .vertical : .horizontal
        brandStack.alignment = .center
        brandStack.spacing = style == .minimal ? 8 : 10
        brandStack.accessibilityIdentifier = "share-brand-stack"
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
        if style == .card {
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
        } else {
            content.isLayoutMarginsRelativeArrangement = false
            content.backgroundColor = .clear
        }
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
