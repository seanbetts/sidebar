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

    private let messageLabel = UILabel()
    private let grabHandleView = UIView()
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
        spacingAfterAccessory: CGFloat = Layout.defaultSpacing,
        footerView: UIView? = nil,
        style: Style = .card
    ) {
        self.style = style
        super.init(frame: .zero)
        setup(
            message: message,
            accessoryView: accessoryView,
            spacingAfterAccessory: spacingAfterAccessory,
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
        spacingAfterAccessory: CGFloat,
        footerView: UIView?
    ) {
        backgroundColor = colorPalette.stateBackground
        configureGrabHandle()

        configureMessageLabel(message: message)

        var arrangedSubviews: [UIView] = [accessoryView, messageLabel]
        if let footerView {
            arrangedSubviews.append(footerView)
        }

        let content = UIStackView(arrangedSubviews: arrangedSubviews)
        configureContentStack(
            content,
            accessoryView: accessoryView,
            spacingAfterAccessory: spacingAfterAccessory,
            hasFooter: footerView != nil
        )
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

    private func configureMessageLabel(message: String) {
        messageLabel.text = message
        messageLabel.font = style == .minimal
            ? .systemFont(ofSize: 15, weight: .regular)
            : .preferredFont(forTextStyle: .subheadline)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
    }

    private func configureContentStack(
        _ content: UIStackView,
        accessoryView: UIView,
        spacingAfterAccessory: CGFloat,
        hasFooter: Bool
    ) {
        content.axis = .vertical
        content.alignment = .center
        content.spacing = Layout.defaultSpacing
        if spacingAfterAccessory != content.spacing {
            content.setCustomSpacing(spacingAfterAccessory, after: accessoryView)
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
