#if canImport(AppKit)
import AppKit

class ShareStateView: NSView {
    enum Style {
        case card
        case minimal
    }

    private enum Layout {
        static let cardCornerRadius: CGFloat = 18
        static let defaultSpacing: CGFloat = 12
        static let cardHorizontalPadding: CGFloat = 20
        static let cardVerticalPadding: CGFloat = 22
        static let contentHorizontalInset: CGFloat = 20
        static let contentVerticalInset: CGFloat = 16
    }

    private struct ColorPalette {
        let hostBackground: NSColor
        let stateBackground: NSColor
        let cardBackground: NSColor

        static func make(for style: Style) -> ColorPalette {
            switch style {
            case .card:
                return ColorPalette(
                    hostBackground: .windowBackgroundColor,
                    stateBackground: .controlBackgroundColor,
                    cardBackground: .controlColor
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

    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let style: Style

    private var colorPalette: ColorPalette {
        ColorPalette.make(for: style)
    }

    private var hostBackgroundColor: NSColor {
        colorPalette.hostBackground
    }

    init(
        message: String,
        accessoryView: NSView,
        spacingAfterAccessory: CGFloat = Layout.defaultSpacing,
        footerView: NSView? = nil,
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

    func applyHostBackground(to hostView: SharePlatformView) {
        hostView.wantsLayer = true
        hostView.layer?.backgroundColor = hostBackgroundColor.cgColor
    }

    func updateMessage(_ message: String) {
        messageLabel.stringValue = message
    }

    private func setup(
        message: String,
        accessoryView: NSView,
        spacingAfterAccessory: CGFloat,
        footerView: NSView?
    ) {
        wantsLayer = true
        layer?.backgroundColor = colorPalette.stateBackground.cgColor

        configureMessageLabel(message: message)

        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .centerX
        content.spacing = Layout.defaultSpacing
        content.translatesAutoresizingMaskIntoConstraints = false

        content.addArrangedSubview(accessoryView)
        content.addArrangedSubview(messageLabel)
        if let footerView {
            content.addArrangedSubview(footerView)
            content.setCustomSpacing(16, after: messageLabel)
        }
        if spacingAfterAccessory != content.spacing {
            content.setCustomSpacing(spacingAfterAccessory, after: accessoryView)
        }

        addSubview(content)

        if style == .card {
            content.wantsLayer = true
            content.layer?.backgroundColor = colorPalette.cardBackground.cgColor
            content.layer?.cornerRadius = Layout.cardCornerRadius
            content.edgeInsets = NSEdgeInsets(
                top: Layout.cardVerticalPadding,
                left: Layout.cardHorizontalPadding,
                bottom: Layout.cardVerticalPadding,
                right: Layout.cardHorizontalPadding
            )
        }

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
            content.widthAnchor.constraint(lessThanOrEqualToConstant: 380)
        ])
    }

    private func configureMessageLabel(message: String) {
        messageLabel.stringValue = message
        messageLabel.font = NSFont.systemFont(ofSize: style == .minimal ? 14 : 13)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.alignment = .center
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.maximumNumberOfLines = 0
        messageLabel.preferredMaxLayoutWidth = 320
    }
}

final class ShareLoadingView: ShareStateView {
    private let loadingImageView: NSImageView

    init(message: String) {
        let loadingImageView = NSImageView()
        loadingImageView.imageScaling = .scaleProportionallyUpOrDown
        loadingImageView.animates = true
        loadingImageView.translatesAutoresizingMaskIntoConstraints = false
        loadingImageView.image = ShareLoadingAsset.image(for: NSApp.effectiveAppearance)
        self.loadingImageView = loadingImageView
        super.init(message: message, accessoryView: loadingImageView)
        NSLayoutConstraint.activate([
            loadingImageView.widthAnchor.constraint(equalToConstant: 44),
            loadingImageView.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        loadingImageView.image = ShareLoadingAsset.image(for: effectiveAppearance)
    }
}

final class ShareErrorView: ShareStateView {
    private enum Layout {
        static let iconSize: CGFloat = 44
    }

    init(message: String) {
        let iconImageView = NSImageView()
        iconImageView.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)
        iconImageView.contentTintColor = .systemRed
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.heightAnchor.constraint(equalToConstant: Layout.iconSize).isActive = true
        iconImageView.widthAnchor.constraint(equalToConstant: Layout.iconSize).isActive = true

        super.init(
            message: message,
            accessoryView: iconImageView,
            spacingAfterAccessory: 20,
            style: .minimal
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class ShareSuccessView: ShareStateView {
    private enum Layout {
        static let iconSize: CGFloat = 44
        static let checkmarkSize: CGFloat = 28
    }

    init(message: String) {
        let iconContainerView = NSView()
        iconContainerView.wantsLayer = true
        iconContainerView.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        iconContainerView.layer?.cornerRadius = Layout.iconSize / 2
        iconContainerView.translatesAutoresizingMaskIntoConstraints = false
        iconContainerView.heightAnchor.constraint(equalToConstant: Layout.iconSize).isActive = true
        iconContainerView.widthAnchor.constraint(equalToConstant: Layout.iconSize).isActive = true

        let symbolConfig = NSImage.SymbolConfiguration(pointSize: Layout.checkmarkSize, weight: .bold)
        let checkmarkImageView = NSImageView()
        let checkmark = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfig)
        checkmarkImageView.image = checkmark
        checkmarkImageView.contentTintColor = .white
        checkmarkImageView.imageScaling = .scaleProportionallyUpOrDown
        checkmarkImageView.translatesAutoresizingMaskIntoConstraints = false
        iconContainerView.addSubview(checkmarkImageView)
        NSLayoutConstraint.activate([
            checkmarkImageView.centerXAnchor.constraint(equalTo: iconContainerView.centerXAnchor),
            checkmarkImageView.centerYAnchor.constraint(equalTo: iconContainerView.centerYAnchor)
        ])

        super.init(
            message: message,
            accessoryView: iconContainerView,
            spacingAfterAccessory: 10,
            style: .minimal
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class ShareProgressView: ShareStateView {
    private let progressView = NSProgressIndicator()

    private(set) var progress: Float = 0

    init(message: String) {
        progressView.style = .bar
        progressView.isIndeterminate = false
        progressView.minValue = 0
        progressView.maxValue = 1
        progressView.doubleValue = 0
        progressView.controlSize = .regular
        progressView.translatesAutoresizingMaskIntoConstraints = false

        let progressContainer = NSView()
        progressContainer.translatesAutoresizingMaskIntoConstraints = false
        progressContainer.addSubview(progressView)
        NSLayoutConstraint.activate([
            progressView.leadingAnchor.constraint(equalTo: progressContainer.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: progressContainer.trailingAnchor),
            progressView.centerYAnchor.constraint(equalTo: progressContainer.centerYAnchor),
            progressContainer.widthAnchor.constraint(equalToConstant: 220),
            progressContainer.heightAnchor.constraint(equalToConstant: 30)
        ])

        super.init(message: message, accessoryView: progressContainer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateProgress(_ value: Float, message: String? = nil) {
        progress = value
        progressView.doubleValue = Double(value)
        if let message {
            updateMessage(message)
        }
    }
}
#endif
