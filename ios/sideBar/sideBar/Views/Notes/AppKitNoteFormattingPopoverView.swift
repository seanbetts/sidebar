#if os(macOS)
import AppKit
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class AppKitNoteFormattingPopoverView: NSView {
    private struct InlineActionItem {
        let identifier: String
        let symbol: String
        let action: (@MainActor @Sendable () -> Void)?
    }

    private final class ActionButton: NSButton {
        var onClick: (@MainActor @Sendable () -> Void)?

        init() {
            super.init(frame: .zero)
            target = self
            action = #selector(handleClick)
            isBordered = false
            bezelStyle = .regularSquare
            translatesAutoresizingMaskIntoConstraints = false
            setButtonType(.momentaryPushIn)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        @objc private func handleClick() {
            onClick?()
        }
    }

    private let backgroundEffectView = NSVisualEffectView()
    private let contentStack = NSStackView()
    private let textStyleScrollView = NSScrollView()
    private let textStyleDocumentView = NSView()
    private let textStyleStrip = NSStackView()
    private let inlineActionsRow = NSStackView()
    private let blockActionsRow = NSStackView()
    private let onDismissRequested: @MainActor @Sendable () -> Void
    private var currentConfiguration: NoteFormattingBarConfiguration
    private var textStyleButtons: [NoteTextStyle: ActionButton] = [:]
    private var inlineButtons: [String: ActionButton] = [:]
    private var widthConstraint: NSLayoutConstraint?
    private static let preferredPopoverWidth: CGFloat = 400

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

        for style in orderedTextStyles {
            guard let button = textStyleButtons[style] else { continue }
            let isEnabled = configuration.canApplyTextStyle(style)
            button.isEnabled = isEnabled
            button.attributedTitle = attributedTextStyleTitle(
                for: style,
                isEnabled: isEnabled
            )
            button.contentTintColor = isEnabled ? .labelColor : .secondaryLabelColor
            button.layer?.backgroundColor = configuration.activeTextStyle == style
                ? NSColor.quaternaryLabelColor.withAlphaComponent(0.28).cgColor
                : NSColor.clear.cgColor
        }

        updateInlineButtons()
    }

    func preferredSize(maxWidth: CGFloat) -> CGSize {
        let resolvedWidth = min(maxWidth, Self.preferredPopoverWidth)
        widthConstraint?.constant = resolvedWidth
        frame.size = CGSize(width: resolvedWidth, height: 260)
        layoutSubtreeIfNeeded()
        let fitted = contentStack.fittingSize
        return CGSize(width: resolvedWidth, height: max(fitted.height + 32, 188))
    }
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
private extension AppKitNoteFormattingPopoverView {
    private var orderedTextStyles: [NoteTextStyle] {
        [.title, .heading, .subheading, .body]
    }

    private var inlineGroupDefinitions: [(String, [InlineActionItem])] {
        [
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
                        action: nil
                    )
                ]
            )
        ]
    }

    private var blockGroupDefinitions: [(String, [InlineActionItem])] {
        [
            ("note-formatting-link-group", [
                InlineActionItem(identifier: "note-formatting-link", symbol: "link", action: nil)
            ]),
            ("note-formatting-future-list-group", [
                InlineActionItem(identifier: "note-formatting-unordered-list", symbol: "list.bullet", action: nil),
                InlineActionItem(identifier: "note-formatting-ordered-list", symbol: "list.number", action: nil),
                InlineActionItem(identifier: "note-formatting-checklist", symbol: "checklist", action: nil)
            ]),
            ("note-formatting-future-blockquote-group", [
                InlineActionItem(identifier: "note-formatting-blockquote", symbol: "text.quote", action: nil)
            ])
        ]
    }

    private func setUpViewHierarchy() {
        identifier = NSUserInterfaceItemIdentifier("note-formatting-popover")
        wantsLayer = true

        setUpBackground()
        setUpContentStack()
        setUpTextStyleStrip()
        setUpActionRows()
        setUpConstraints()
    }

    private func setUpBackground() {
        backgroundEffectView.identifier = NSUserInterfaceItemIdentifier("note-formatting-popover-glass")
        backgroundEffectView.translatesAutoresizingMaskIntoConstraints = false
        backgroundEffectView.material = .hudWindow
        backgroundEffectView.state = .active
        backgroundEffectView.blendingMode = .withinWindow
        backgroundEffectView.wantsLayer = true
        backgroundEffectView.layer?.cornerRadius = 26
        backgroundEffectView.layer?.cornerCurve = .continuous
        backgroundEffectView.layer?.masksToBounds = true
        addSubview(backgroundEffectView)
    }

    private func setUpContentStack() {
        contentStack.orientation = .vertical
        contentStack.alignment = .centerX
        contentStack.spacing = 14
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)
    }

    private func setUpTextStyleStrip() {
        textStyleScrollView.identifier = NSUserInterfaceItemIdentifier("note-formatting-text-style-strip")
        textStyleScrollView.translatesAutoresizingMaskIntoConstraints = false
        textStyleScrollView.borderType = .noBorder
        textStyleScrollView.drawsBackground = false
        textStyleScrollView.hasHorizontalScroller = false
        textStyleScrollView.hasVerticalScroller = false
        contentStack.addArrangedSubview(textStyleScrollView)

        textStyleDocumentView.translatesAutoresizingMaskIntoConstraints = false
        textStyleScrollView.documentView = textStyleDocumentView

        textStyleStrip.identifier = NSUserInterfaceItemIdentifier("note-formatting-text-style-buttons")
        textStyleStrip.orientation = .horizontal
        textStyleStrip.alignment = .centerY
        textStyleStrip.spacing = 4
        textStyleStrip.translatesAutoresizingMaskIntoConstraints = false
        textStyleDocumentView.addSubview(textStyleStrip)

        for style in orderedTextStyles {
            let button = makeTextStyleButton(for: style)
            textStyleButtons[style] = button
            textStyleStrip.addArrangedSubview(button)
        }
    }

    private func setUpActionRows() {
        configureActionRow(inlineActionsRow)
        configureActionRow(blockActionsRow)
        inlineActionsRow.identifier = NSUserInterfaceItemIdentifier("note-formatting-inline-actions-row")
        blockActionsRow.identifier = NSUserInterfaceItemIdentifier("note-formatting-bottom-actions-row")

        inlineGroupDefinitions.forEach { identifier, items in
            inlineActionsRow.addArrangedSubview(makeInlineGroup(identifier: identifier, items: items))
        }
        blockGroupDefinitions.forEach { identifier, items in
            blockActionsRow.addArrangedSubview(makeInlineGroup(identifier: identifier, items: items))
        }

        contentStack.addArrangedSubview(inlineActionsRow)
        contentStack.addArrangedSubview(blockActionsRow)
    }

    private func configureActionRow(_ row: NSStackView) {
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setUpConstraints() {
        widthConstraint = widthAnchor.constraint(equalToConstant: Self.preferredPopoverWidth)
        widthConstraint?.isActive = true

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

            textStyleDocumentView.leadingAnchor.constraint(equalTo: textStyleScrollView.contentView.leadingAnchor),
            textStyleDocumentView.trailingAnchor.constraint(equalTo: textStyleScrollView.contentView.trailingAnchor),
            textStyleDocumentView.topAnchor.constraint(equalTo: textStyleScrollView.contentView.topAnchor),
            textStyleDocumentView.bottomAnchor.constraint(equalTo: textStyleScrollView.contentView.bottomAnchor),
            textStyleDocumentView.heightAnchor.constraint(equalTo: textStyleScrollView.contentView.heightAnchor),
            textStyleDocumentView.widthAnchor.constraint(greaterThanOrEqualTo: textStyleScrollView.contentView.widthAnchor),

            textStyleStrip.leadingAnchor.constraint(equalTo: textStyleDocumentView.leadingAnchor),
            textStyleStrip.trailingAnchor.constraint(lessThanOrEqualTo: textStyleDocumentView.trailingAnchor),
            textStyleStrip.topAnchor.constraint(equalTo: textStyleDocumentView.topAnchor),
            textStyleStrip.bottomAnchor.constraint(equalTo: textStyleDocumentView.bottomAnchor)
        ])
    }

    private func makeTextStyleButton(for style: NoteTextStyle) -> ActionButton {
        let button = ActionButton()
        button.identifier = NSUserInterfaceItemIdentifier("note-formatting-text-style-\(style.rawValue)")
        button.title = style.displayName
        button.wantsLayer = true
        button.layer?.cornerRadius = 16
        button.layer?.cornerCurve = .continuous
        button.contentTintColor = .labelColor
        button.onClick = { [weak self] in
            guard let self else { return }
            self.currentConfiguration.selectTextStyle(style)
            self.onDismissRequested()
        }
        button.setButtonType(.momentaryPushIn)
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.font = NoteTextStyleTypography.platformFont(
            for: style,
            baseFontSize: NoteTextTypography.defaultBodyFontSize
        )
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 56).isActive = true
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        return button
    }

    private func attributedTextStyleTitle(for style: NoteTextStyle, isEnabled: Bool) -> NSAttributedString {
        NSAttributedString(
            string: style.displayName,
            attributes: [
                .font: NoteTextStyleTypography.platformFont(
                    for: style,
                    baseFontSize: NoteTextTypography.defaultBodyFontSize
                ),
                .foregroundColor: isEnabled ? NSColor.labelColor : NSColor.secondaryLabelColor
            ]
        )
    }

    private func makeInlineGroup(identifier: String, items: [InlineActionItem]) -> NSView {
        let container = NSVisualEffectView()
        container.identifier = NSUserInterfaceItemIdentifier(identifier)
        container.translatesAutoresizingMaskIntoConstraints = false
        container.material = .menu
        container.state = .active
        container.blendingMode = .withinWindow
        container.wantsLayer = true
        container.layer?.cornerRadius = 22
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        items.map(makeButton(for:)).forEach { stack.addArrangedSubview($0) }

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    private func makeButton(for item: InlineActionItem) -> ActionButton {
        let button = ActionButton()
        button.identifier = NSUserInterfaceItemIdentifier(item.identifier)
        button.image = NSImage(
            systemSymbolName: item.symbol,
            accessibilityDescription: nil
        )
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = item.action == nil ? .secondaryLabelColor : .labelColor
        button.isEnabled = item.action != nil
        button.onClick = item.action
        button.widthAnchor.constraint(equalToConstant: 58).isActive = true
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
        button.wantsLayer = true
        inlineButtons[item.identifier] = button
        return button
    }

    private func updateInlineButtons() {
        let buttonStates = [
            ("note-formatting-bold", currentConfiguration.isBoldActive),
            ("note-formatting-italic", currentConfiguration.isItalicActive),
            ("note-formatting-underline", currentConfiguration.isUnderlineActive),
            ("note-formatting-strikethrough", currentConfiguration.isStrikethroughActive),
            ("note-formatting-inline-code", currentConfiguration.isInlineCodeActive)
        ]

        for (identifier, isActive) in buttonStates {
            guard let button = inlineButtons[identifier] else { continue }
            button.layer?.backgroundColor = isActive
                ? NSColor.quaternaryLabelColor.withAlphaComponent(0.28).cgColor
                : NSColor.clear.cgColor
            button.layer?.cornerRadius = 14
            button.layer?.cornerCurve = .continuous
        }
    }
}
#endif
