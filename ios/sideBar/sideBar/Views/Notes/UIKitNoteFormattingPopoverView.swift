import SwiftUI
import sideBarShared
#if os(iOS)
import UIKit

@MainActor
@available(iOS 26.0, *)
final class UIKitNoteFormattingPopoverView: UIView {
    static let preferredPopoverWidth: CGFloat = 400

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
        let resolvedWidth = min(maxWidth, Self.preferredPopoverWidth)
        let compressed = systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        guard compressed.width > resolvedWidth else { return compressed }

        let constrained = systemLayoutSizeFitting(
            CGSize(width: resolvedWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return CGSize(width: resolvedWidth, height: constrained.height)
    }
}

@MainActor
@available(iOS 26.0, *)
private extension UIKitNoteFormattingPopoverView {
    private struct InlineActionItem {
        let identifier: String
        let appIcon: AppIcon
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
                    InlineActionItem(identifier: "note-formatting-bold", appIcon: AppIcon.Notes.bold) { [weak self] in
                        self?.currentConfiguration.onBoldTap()
                        self?.onDismissRequested()
                    },
                    InlineActionItem(identifier: "note-formatting-italic", appIcon: AppIcon.Notes.italic) { [weak self] in
                        self?.currentConfiguration.onItalicTap()
                        self?.onDismissRequested()
                    },
                    InlineActionItem(identifier: "note-formatting-underline", appIcon: AppIcon.Notes.underline) { [weak self] in
                        self?.currentConfiguration.onUnderlineTap()
                        self?.onDismissRequested()
                    },
                    InlineActionItem(identifier: "note-formatting-strikethrough", appIcon: AppIcon.Notes.strikethrough) { [weak self] in
                        self?.currentConfiguration.onStrikethroughTap()
                        self?.onDismissRequested()
                    }
                ]
            ),
            (
                "note-formatting-code-group",
                [
                    InlineActionItem(identifier: "note-formatting-inline-code", appIcon: AppIcon.Notes.inlineCode) { [weak self] in
                        self?.currentConfiguration.onInlineCodeTap()
                        self?.onDismissRequested()
                    },
                    InlineActionItem(
                        identifier: "note-formatting-code-block",
                        appIcon: AppIcon.Notes.codeBlock,
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

        let blockquoteAction: (@MainActor @Sendable () -> Void)?
        if currentConfiguration.isBlockquoteEnabled {
            blockquoteAction = { [weak self] in
                self?.currentConfiguration.onBlockquoteTap()
                self?.onDismissRequested()
            }
        } else {
            blockquoteAction = nil
        }

        return [
            (
                "note-formatting-future-list-group",
                [
                    InlineActionItem(
                        identifier: "note-formatting-unordered-list",
                        appIcon: AppIcon.Notes.unorderedList,
                        action: unorderedListAction
                    ),
                    InlineActionItem(
                        identifier: "note-formatting-ordered-list",
                        appIcon: AppIcon.Notes.orderedList,
                        action: orderedListAction
                    ),
                    InlineActionItem(
                        identifier: "note-formatting-checklist",
                        appIcon: AppIcon.Notes.checklist,
                        action: checklistAction
                    )
                ]
            ),
            (
                "note-formatting-future-blockquote-group",
                [
                    InlineActionItem(
                        identifier: "note-formatting-blockquote",
                        appIcon: AppIcon.Notes.blockquote,
                        action: blockquoteAction
                    )
                ]
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
        button.configuration = pillButtonConfiguration(appIcon: item.appIcon, enabled: item.action != nil)
        button.isEnabled = item.action != nil
        if let action = item.action {
            button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        }
        button.widthAnchor.constraint(equalToConstant: 58).isActive = true
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
        return button
    }

    func pillButtonConfiguration(appIcon: AppIcon, enabled: Bool) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(appIcon: appIcon)
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
            ("note-formatting-bold", currentConfiguration.isBoldActive, currentConfiguration.isEnabled, AppIcon.Notes.bold),
            ("note-formatting-italic", currentConfiguration.isItalicActive, currentConfiguration.isEnabled, AppIcon.Notes.italic),
            ("note-formatting-underline", currentConfiguration.isUnderlineActive, currentConfiguration.isEnabled, AppIcon.Notes.underline),
            (
                "note-formatting-strikethrough",
                currentConfiguration.isStrikethroughActive,
                currentConfiguration.isEnabled,
                AppIcon.Notes.strikethrough
            ),
            (
                "note-formatting-inline-code",
                currentConfiguration.isInlineCodeActive,
                currentConfiguration.isEnabled,
                AppIcon.Notes.inlineCode
            ),
            (
                "note-formatting-code-block",
                currentConfiguration.isCodeBlockActive,
                currentConfiguration.isCodeBlockEnabled,
                AppIcon.Notes.codeBlock
            ),
            (
                "note-formatting-unordered-list",
                currentConfiguration.isUnorderedListActive,
                currentConfiguration.isUnorderedListEnabled,
                AppIcon.Notes.unorderedList
            ),
            (
                "note-formatting-ordered-list",
                currentConfiguration.isOrderedListActive,
                currentConfiguration.isOrderedListEnabled,
                AppIcon.Notes.orderedList
            ),
            (
                "note-formatting-checklist",
                currentConfiguration.isChecklistActive,
                currentConfiguration.isChecklistEnabled,
                AppIcon.Notes.checklist
            ),
            (
                "note-formatting-blockquote",
                currentConfiguration.isBlockquoteActive,
                currentConfiguration.isBlockquoteEnabled,
                AppIcon.Notes.blockquote
            )
        ]

        for (identifier, isActive, isEnabled, appIcon) in buttonStates {
            updateButton(identifier: identifier, active: isActive, enabled: isEnabled, appIcon: appIcon)
        }
    }

    func updateButton(identifier: String, active: Bool, enabled: Bool, appIcon: AppIcon) {
        guard let button = findDescendantButton(in: self, accessibilityIdentifier: identifier) else { return }
        var configuration = pillButtonConfiguration(appIcon: appIcon, enabled: enabled)
        if active {
            configuration.background = selectedButtonBackground()
        }
        button.configuration = configuration
        button.isEnabled = enabled
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
