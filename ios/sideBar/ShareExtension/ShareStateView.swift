#if canImport(UIKit)
import UIKit

class ShareStateView: UIView {
    enum Style {
        case card
        case minimal
    }

    private enum Layout {
        static let grabHandleWidth: CGFloat = 36
        static let grabHandleHeight: CGFloat = 5
        static let grabHandleTopInset: CGFloat = 8
        static let minimumSpacingBelowGrabHandle: CGFloat = 12
        static let cardCornerRadius: CGFloat = 20
        static let defaultSpacing: CGFloat = 12
        static let cardHorizontalPadding: CGFloat = 22
        static let cardVerticalPadding: CGFloat = 24
        static let contentHorizontalInset: CGFloat = 20
        static let contentVerticalInset: CGFloat = 16
        static let logoSize: CGFloat = 34
    }

    private struct ColorPalette {
        let hostBackground: UIColor
        let stateBackground: UIColor
        let cardBackground: UIColor

        static func make(for style: Style) -> ColorPalette {
            switch style {
            case .card:
                return ColorPalette(
                    hostBackground: .systemBackground,
                    stateBackground: .systemBackground,
                    cardBackground: .secondarySystemBackground
                )
            case .minimal:
                return ColorPalette(
                    hostBackground: .clear,
                    stateBackground: .clear,
                    cardBackground: .clear
                )
            }
        }
    }

    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let logoImageView = UIImageView()
    private let grabHandleView = UIView()
    private let brandStack = UIStackView()
    private let style: Style

    private var colorPalette: ColorPalette {
        ColorPalette.make(for: style)
    }

    var hostBackgroundColor: UIColor {
        colorPalette.hostBackground
    }

    func applyHostBackground(to hostView: SharePlatformView) {
        hostView.backgroundColor = hostBackgroundColor
    }

    init(
        message: String,
        accessoryView: UIView,
        spacingAfterTitle: CGFloat = Layout.defaultSpacing,
        footerView: UIView? = nil,
        style: Style = .card
    ) {
        self.style = style
        super.init(frame: .zero)
        observeUserInterfaceStyleChanges()
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

    private func observeUserInterfaceStyleChanges() {
        _ = registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _: UITraitCollection) in
            self.refreshBrandLogo()
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
        backgroundColor = colorPalette.stateBackground
        configureGrabHandle()

        configureLabels(message: message)
        configureBrandStack()

        var arrangedSubviews: [UIView] = [brandStack, accessoryView, messageLabel]
        if let footerView {
            arrangedSubviews.append(footerView)
        }

        let content = UIStackView(arrangedSubviews: arrangedSubviews)
        configureContentStack(content, spacingAfterTitle: spacingAfterTitle, hasFooter: footerView != nil)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        activateLayoutConstraints(for: content)
    }

    private func configureGrabHandle() {
        let grabHandleColor = UIColor { traits in
            let base = UIColor.tertiaryLabel.resolvedColor(with: traits)
            return base.withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.45 : 0.3)
        }
        grabHandleView.backgroundColor = grabHandleColor
        grabHandleView.layer.cornerRadius = Layout.grabHandleHeight / 2
        grabHandleView.layer.cornerCurve = .continuous
        grabHandleView.accessibilityIdentifier = "share-grab-handle"
        grabHandleView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grabHandleView)
    }

    private func configureLabels(message: String) {
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
    }

    private func configureBrandStack() {
        brandStack.axis = .vertical
        brandStack.alignment = .center
        brandStack.spacing = 8
        brandStack.accessibilityIdentifier = "share-brand-stack"
        brandStack.addArrangedSubview(logoImageView)
        brandStack.addArrangedSubview(titleLabel)
    }

    private func configureContentStack(
        _ content: UIStackView,
        spacingAfterTitle: CGFloat,
        hasFooter: Bool
    ) {
        content.axis = .vertical
        content.alignment = .center
        content.spacing = Layout.defaultSpacing
        if spacingAfterTitle != content.spacing {
            content.setCustomSpacing(spacingAfterTitle, after: brandStack)
        }
        if hasFooter {
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
            content.backgroundColor = colorPalette.cardBackground
            content.layer.cornerRadius = Layout.cardCornerRadius
            content.layer.cornerCurve = .continuous
            content.accessibilityIdentifier = "share-state-card"
            return
        }
        content.isLayoutMarginsRelativeArrangement = false
        content.backgroundColor = .clear
    }

    private func activateLayoutConstraints(for content: UIView) {
        NSLayoutConstraint.activate([
            grabHandleView.topAnchor.constraint(
                equalTo: safeAreaLayoutGuide.topAnchor,
                constant: Layout.grabHandleTopInset
            ),
            grabHandleView.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor),
            grabHandleView.widthAnchor.constraint(equalToConstant: Layout.grabHandleWidth),
            grabHandleView.heightAnchor.constraint(equalToConstant: Layout.grabHandleHeight),
            content.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor),
            content.centerYAnchor.constraint(equalTo: safeAreaLayoutGuide.centerYAnchor),
            content.topAnchor.constraint(
                greaterThanOrEqualTo: safeAreaLayoutGuide.topAnchor,
                constant: Layout.contentVerticalInset
            ),
            content.topAnchor.constraint(
                greaterThanOrEqualTo: grabHandleView.bottomAnchor,
                constant: Layout.minimumSpacingBelowGrabHandle
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
#endif
