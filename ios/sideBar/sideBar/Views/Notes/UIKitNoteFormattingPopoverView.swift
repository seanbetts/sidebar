import SwiftUI
#if os(iOS)
import UIKit

@MainActor
@available(iOS 26.0, *)
final class UIKitNoteFormattingPopoverView: UIView {
    private let backgroundEffectView = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
    private let contentStack = UIStackView()
    private let textStyleScrollView = UIScrollView()
    private let textStyleContentView = UIView()
    private let textStyleStrip = UIStackView()
    private let inlineActionsRow = UIStackView()
    private let blockActionsRow = UIStackView()
    private var textStyleButtons: [NoteTextStyle: UIButton] = [:]
    private let onDismissRequested: @MainActor @Sendable () -> Void
    private var currentConfiguration: NoteFormattingBarConfiguration

    init(
        configuration: NoteFormattingBarConfiguration,
        onDismissRequested: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.currentConfiguration = configuration
        self.onDismissRequested = onDismissRequested
        super.init(frame: .zero)
        setUpViewHierarchy()
        apply(configuration: configuration)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(configuration: NoteFormattingBarConfiguration) {
        currentConfiguration = configuration
        for (style, button) in textStyleButtons {
            let isEnabled = configuration.canApplyTextStyle(style)
            button.configuration = textStyleButtonConfiguration(
                style: style,
                isActive: configuration.activeTextStyle == style,
                isEnabled: isEnabled
            )
            button.isEnabled = isEnabled
        }
        updateInlineButtons()
    }

    func preferredSize(maxWidth: CGFloat) -> CGSize {
        let compressed = systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        guard compressed.width > maxWidth else { return compressed }

        let constrained = systemLayoutSizeFitting(
            CGSize(width: maxWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return CGSize(width: maxWidth, height: constrained.height)
    }
}

@MainActor
@available(iOS 26.0, *)
private extension UIKitNoteFormattingPopoverView {
    private struct InlineActionItem {
        let identifier: String
        let symbol: String
        let action: (@MainActor @Sendable () -> Void)?
    }

    private var inlineGroupDefinitions: [(String, [InlineActionItem])] {
        let codeBlockAction: (@MainActor @Sendable () -> Void)?
        if currentConfiguration.isCodeBlockEnabled {
            codeBlockAction = { [weak self] in
                self?.currentConfiguration.onCodeBlockTap()
                self?.onDismissRequested()
            }
        } else {
            codeBlockAction = nil
        }
        return [
            (
                "note-formatting-inline-group",
                [
                    InlineActionItem(identifier: "note-formatting-bold", symbol: "bold") { [weak self] in
                        self?.currentConfiguration.onBoldTap()
                        self?.onDismissRequested()
                    },
                    InlineActionItem(identifier: "note-formatting-italic", symbol: "italic") { [weak self] in
                        self?.currentConfiguration.onItalicTap()
                        self?.onDismissRequested()
                    },
                    InlineActionItem(identifier: "note-formatting-underline", symbol: "underline") { [weak self] in
                        self?.currentConfiguration.onUnderlineTap()
                        self?.onDismissRequested()
                    },
                    InlineActionItem(identifier: "note-formatting-strikethrough", symbol: "strikethrough") { [weak self] in
                        self?.currentConfiguration.onStrikethroughTap()
                        self?.onDismissRequested()
                    }
                ]
            ),
            (
                "note-formatting-code-group",
                [
                    InlineActionItem(identifier: "note-formatting-inline-code", symbol: "curlybraces") { [weak self] in
                        self?.currentConfiguration.onInlineCodeTap()
                        self?.onDismissRequested()
                    },
                    InlineActionItem(
                        identifier: "note-formatting-code-block",
                        symbol: "chevron.left.forwardslash.chevron.right",
                        action: codeBlockAction
                    )
                ]
            )
        ]
    }

    private var blockGroupDefinitions: [(String, [InlineActionItem])] {
        [
            (
                "note-formatting-future-list-group",
                [
                    InlineActionItem(identifier: "note-formatting-unordered-list", symbol: "list.bullet", action: nil),
                    InlineActionItem(identifier: "note-formatting-ordered-list", symbol: "list.number", action: nil),
                    InlineActionItem(identifier: "note-formatting-checklist", symbol: "checklist", action: nil)
                ]
            ),
            (
                "note-formatting-future-blockquote-group",
                [InlineActionItem(identifier: "note-formatting-blockquote", symbol: "text.quote", action: nil)]
            )
        ]
    }

    func setUpViewHierarchy() {
        accessibilityIdentifier = "note-formatting-popover"
        backgroundColor = .clear
        clipsToBounds = false
        setUpBackground()
        setUpContentStack()
        setUpTextStyleStrip()
        setUpActionRows()
        setUpConstraints()
    }

    func setUpBackground() {
        backgroundEffectView.translatesAutoresizingMaskIntoConstraints = false
        backgroundEffectView.accessibilityIdentifier = "note-formatting-popover-glass"
        backgroundEffectView.clipsToBounds = true
        backgroundEffectView.layer.cornerCurve = .continuous
        backgroundEffectView.layer.cornerRadius = 26
        addSubview(backgroundEffectView)
    }

    func setUpContentStack() {
        contentStack.axis = .vertical
        contentStack.alignment = .center
        contentStack.spacing = 14
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)
    }

    func setUpTextStyleStrip() {
        textStyleScrollView.translatesAutoresizingMaskIntoConstraints = false
        textStyleScrollView.showsHorizontalScrollIndicator = false
        textStyleScrollView.alwaysBounceHorizontal = false
        textStyleScrollView.accessibilityIdentifier = "note-formatting-text-style-strip"
        contentStack.addArrangedSubview(textStyleScrollView)

        textStyleContentView.translatesAutoresizingMaskIntoConstraints = false
        textStyleScrollView.addSubview(textStyleContentView)

        textStyleStrip.axis = .horizontal
        textStyleStrip.alignment = .center
        textStyleStrip.spacing = 4
        textStyleStrip.accessibilityIdentifier = "note-formatting-text-style-buttons"
        textStyleStrip.translatesAutoresizingMaskIntoConstraints = false
        textStyleContentView.addSubview(textStyleStrip)

        for style in NoteTextStyle.allCases {
            let button = makeTextStyleButton(for: style)
            textStyleButtons[style] = button
            textStyleStrip.addArrangedSubview(button)
        }
    }

    func setUpActionRows() {
        configureActionRow(inlineActionsRow)
        configureActionRow(blockActionsRow)
        inlineActionsRow.accessibilityIdentifier = "note-formatting-inline-actions-row"
        blockActionsRow.accessibilityIdentifier = "note-formatting-bottom-actions-row"

        inlineGroupDefinitions.forEach { identifier, items in
            inlineActionsRow.addArrangedSubview(makeInlineGroup(identifier: identifier, items: items))
        }

        blockGroupDefinitions.forEach { identifier, items in
            blockActionsRow.addArrangedSubview(makeInlineGroup(identifier: identifier, items: items))
        }

        contentStack.addArrangedSubview(inlineActionsRow)
        contentStack.addArrangedSubview(blockActionsRow)
    }

    private func configureActionRow(_ row: UIStackView) {
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
    }

    func setUpConstraints() {
        NSLayoutConstraint.activate([
            backgroundEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundEffectView.topAnchor.constraint(equalTo: topAnchor),
            backgroundEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            contentStack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),

            textStyleScrollView.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            textStyleScrollView.heightAnchor.constraint(equalToConstant: 60),

            textStyleContentView.leadingAnchor.constraint(equalTo: textStyleScrollView.contentLayoutGuide.leadingAnchor),
            textStyleContentView.trailingAnchor.constraint(equalTo: textStyleScrollView.contentLayoutGuide.trailingAnchor),
            textStyleContentView.topAnchor.constraint(equalTo: textStyleScrollView.contentLayoutGuide.topAnchor),
            textStyleContentView.bottomAnchor.constraint(equalTo: textStyleScrollView.contentLayoutGuide.bottomAnchor),
            textStyleContentView.heightAnchor.constraint(equalTo: textStyleScrollView.frameLayoutGuide.heightAnchor),
            textStyleContentView.widthAnchor.constraint(greaterThanOrEqualTo: textStyleScrollView.frameLayoutGuide.widthAnchor),

            textStyleStrip.leadingAnchor.constraint(equalTo: textStyleContentView.leadingAnchor),
            textStyleStrip.trailingAnchor.constraint(lessThanOrEqualTo: textStyleContentView.trailingAnchor),
            textStyleStrip.topAnchor.constraint(equalTo: textStyleContentView.topAnchor),
            textStyleStrip.bottomAnchor.constraint(equalTo: textStyleContentView.bottomAnchor)
        ])
    }

    func makeTextStyleButton(for style: NoteTextStyle) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityIdentifier = "note-formatting-text-style-\(style.rawValue)"
        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.currentConfiguration.selectTextStyle(style)
            self.onDismissRequested()
        }, for: .touchUpInside)
        return button
    }

    func textStyleButtonConfiguration(
        style: NoteTextStyle,
        isActive: Bool,
        isEnabled: Bool
    ) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.plain()
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        configuration.background = isActive ? selectedButtonBackground() : .clear()
        var titleAttributes = AttributeContainer()
        titleAttributes.font = NoteTextStyleTypography.platformFont(
            for: style,
            baseFontSize: NoteTextTypography.defaultBodyFontSize
        )
        titleAttributes.foregroundColor = isEnabled ? UIColor.label : UIColor.secondaryLabel
        configuration.attributedTitle = AttributedString(style.displayName, attributes: titleAttributes)
        return configuration
    }

    private func makeInlineGroup(identifier: String, items: [InlineActionItem]) -> UIView {
        let stack = UIStackView(arrangedSubviews: items.map(makeButton(for:)))
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        let effectView = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
        effectView.accessibilityIdentifier = identifier
        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.clipsToBounds = true
        effectView.layer.cornerRadius = 22
        effectView.layer.cornerCurve = .continuous
        effectView.contentView.addSubview(stack)
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.accessibilityIdentifier = identifier
        container.addSubview(effectView)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            effectView.topAnchor.constraint(equalTo: container.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: effectView.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effectView.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effectView.contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effectView.contentView.bottomAnchor)
        ])

        return container
    }

    private func makeButton(for item: InlineActionItem) -> UIButton {
        let button = UIButton(type: .system)
        button.accessibilityIdentifier = item.identifier
        button.translatesAutoresizingMaskIntoConstraints = false
        button.configuration = pillButtonConfiguration(symbol: item.symbol, enabled: item.action != nil)
        button.isEnabled = item.action != nil
        if let action = item.action {
            button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        }
        button.widthAnchor.constraint(equalToConstant: 58).isActive = true
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
        return button
    }

    func pillButtonConfiguration(symbol: String, enabled: Bool) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: symbol)
        configuration.baseForegroundColor = enabled ? .label : .secondaryLabel
        configuration.background = .clear()
        return configuration
    }

    func selectedButtonBackground() -> UIBackgroundConfiguration {
        var background = UIButton.Configuration.plain().background
        background.backgroundColor = UIColor.secondaryLabel.withAlphaComponent(0.12)
        return background
    }

    func updateInlineButtons() {
        let buttonStates = [
            ("note-formatting-bold", currentConfiguration.isBoldActive, "bold"),
            ("note-formatting-italic", currentConfiguration.isItalicActive, "italic"),
            ("note-formatting-underline", currentConfiguration.isUnderlineActive, "underline"),
            ("note-formatting-strikethrough", currentConfiguration.isStrikethroughActive, "strikethrough"),
            ("note-formatting-inline-code", currentConfiguration.isInlineCodeActive, "curlybraces"),
            ("note-formatting-code-block", currentConfiguration.isCodeBlockActive, "chevron.left.forwardslash.chevron.right")
        ]

        for (identifier, isActive, symbol) in buttonStates {
            updateButton(identifier: identifier, active: isActive, symbol: symbol)
        }
    }

    func updateButton(identifier: String, active: Bool, symbol: String) {
        guard let button = findDescendantButton(in: self, accessibilityIdentifier: identifier) else { return }
        var configuration = pillButtonConfiguration(symbol: symbol, enabled: true)
        if active {
            configuration.background = selectedButtonBackground()
        }
        button.configuration = configuration
    }

    func findDescendantButton(in view: UIView, accessibilityIdentifier: String) -> UIButton? {
        if let button = view as? UIButton, button.accessibilityIdentifier == accessibilityIdentifier {
            return button
        }
        for subview in view.subviews {
            if let match = findDescendantButton(in: subview, accessibilityIdentifier: accessibilityIdentifier) {
                return match
            }
        }
        return nil
    }
}
#endif
