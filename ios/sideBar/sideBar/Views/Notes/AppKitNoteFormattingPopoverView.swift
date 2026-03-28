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
        var contentInsets = NSEdgeInsetsZero {
            didSet {
                invalidateIntrinsicContentSize()
            }
        }

        override var title: String {
            didSet {
                invalidateIntrinsicContentSize()
            }
        }

        override var attributedTitle: NSAttributedString {
            didSet {
                invalidateIntrinsicContentSize()
            }
        }

        override var intrinsicContentSize: NSSize {
            var size = attributedTitle.length > 0 ? attributedTitle.size() : super.intrinsicContentSize
            size.width = ceil(size.width + contentInsets.left + contentInsets.right)
            size.height = ceil(size.height + contentInsets.top + contentInsets.bottom)
            return size
        }

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

    private let backgroundEffectView = NSGlassEffectView()
    private let contentContainerView = NSView()
    private let contentStack = NSStackView()
    private let textStyleScrollView = NSScrollView()
    private let textStyleDocumentView = NSView()
    private let textStyleStrip = NSStackView()
    private let leadingTextStyleSpacer = NSView()
    private let trailingTextStyleSpacer = NSView()
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
        let unorderedListAction: (@MainActor @Sendable () -> Void)?
        if currentConfiguration.isUnorderedListEnabled {
            unorderedListAction = { [weak self] in
                self?.currentConfiguration.onUnorderedListTap()
                self?.onDismissRequested()
            }
        } else {
            unorderedListAction = nil
        }

        let orderedListAction: (@MainActor @Sendable () -> Void)?
        if currentConfiguration.isOrderedListEnabled {
            orderedListAction = { [weak self] in
                self?.currentConfiguration.onOrderedListTap()
                self?.onDismissRequested()
            }
        } else {
            orderedListAction = nil
        }

        let checklistAction: (@MainActor @Sendable () -> Void)?
        if currentConfiguration.isChecklistEnabled {
            checklistAction = { [weak self] in
                self?.currentConfiguration.onChecklistTap()
                self?.onDismissRequested()
            }
        } else {
            checklistAction = nil
        }

        return [
            ("note-formatting-future-list-group", [
                InlineActionItem(
                    identifier: "note-formatting-unordered-list",
                    symbol: "list.bullet",
                    action: unorderedListAction
                ),
                InlineActionItem(
                    identifier: "note-formatting-ordered-list",
                    symbol: "list.number",
                    action: orderedListAction
                ),
                InlineActionItem(
                    identifier: "note-formatting-checklist",
                    symbol: "checklist",
                    action: checklistAction
                )
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
        backgroundEffectView.style = .regular
        backgroundEffectView.cornerRadius = 26
        backgroundEffectView.contentView = contentContainerView
        addSubview(backgroundEffectView)
    }

    private func setUpContentStack() {
        contentContainerView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .vertical
        contentStack.alignment = .centerX
        contentStack.spacing = 14
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentContainerView.addSubview(contentStack)
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
        textStyleStrip.distribution = .equalSpacing
        textStyleStrip.spacing = 4
        textStyleStrip.translatesAutoresizingMaskIntoConstraints = false
        textStyleDocumentView.addSubview(textStyleStrip)

        configureTextStyleSpacer(leadingTextStyleSpacer)
        configureTextStyleSpacer(trailingTextStyleSpacer)
        textStyleStrip.addArrangedSubview(leadingTextStyleSpacer)

        for style in orderedTextStyles {
            let button = makeTextStyleButton(for: style)
            textStyleButtons[style] = button
            textStyleStrip.addArrangedSubview(button)
        }

        textStyleStrip.addArrangedSubview(trailingTextStyleSpacer)
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

    private func configureTextStyleSpacer(_ spacer: NSView) {
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 0).isActive = true
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
            textStyleStrip.trailingAnchor.constraint(equalTo: textStyleDocumentView.trailingAnchor),
            textStyleStrip.topAnchor.constraint(equalTo: textStyleDocumentView.topAnchor),
            textStyleStrip.bottomAnchor.constraint(equalTo: textStyleDocumentView.bottomAnchor),

            leadingTextStyleSpacer.widthAnchor.constraint(equalTo: trailingTextStyleSpacer.widthAnchor)
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
        button.contentInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
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
        let container = NSGlassEffectView()
        let contentView = NSView()
        container.identifier = NSUserInterfaceItemIdentifier(identifier)
        container.translatesAutoresizingMaskIntoConstraints = false
        container.style = .regular
        container.cornerRadius = 22
        container.contentView = contentView

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        items.map(makeButton(for:)).forEach { stack.addArrangedSubview($0) }

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
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
            ("note-formatting-bold", currentConfiguration.isBoldActive, currentConfiguration.isEnabled),
            ("note-formatting-italic", currentConfiguration.isItalicActive, currentConfiguration.isEnabled),
            ("note-formatting-underline", currentConfiguration.isUnderlineActive, currentConfiguration.isEnabled),
            ("note-formatting-strikethrough", currentConfiguration.isStrikethroughActive, currentConfiguration.isEnabled),
            ("note-formatting-inline-code", currentConfiguration.isInlineCodeActive, currentConfiguration.isEnabled),
            (
                "note-formatting-code-block",
                currentConfiguration.isCodeBlockActive,
                currentConfiguration.isCodeBlockEnabled
            ),
            (
                "note-formatting-unordered-list",
                currentConfiguration.isUnorderedListActive,
                currentConfiguration.isUnorderedListEnabled
            ),
            (
                "note-formatting-ordered-list",
                currentConfiguration.isOrderedListActive,
                currentConfiguration.isOrderedListEnabled
            ),
            (
                "note-formatting-checklist",
                currentConfiguration.isChecklistActive,
                currentConfiguration.isChecklistEnabled
            )
        ]

        for (identifier, isActive, isEnabled) in buttonStates {
            guard let button = inlineButtons[identifier] else { continue }
            button.layer?.backgroundColor = isActive
                ? NSColor.quaternaryLabelColor.withAlphaComponent(0.28).cgColor
                : NSColor.clear.cgColor
            button.layer?.cornerRadius = 14
            button.layer?.cornerCurve = .continuous
            button.isEnabled = isEnabled
            button.contentTintColor = isEnabled ? .labelColor : .secondaryLabelColor
        }
    }
}
#endif
