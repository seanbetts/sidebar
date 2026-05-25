#if os(iOS)
import UIKit

struct UIKitNoteTextEditorRenderSignature: Equatable {
    let renderGeneration: UInt64
    let baseFontSize: CGFloat
}

private struct UIKitNoteTextEditorViewportSnapshot: Equatable {
    let contentOffset: CGPoint
    let selectedRange: NSRange
    let selectionViewportAnchorY: CGFloat?
}

struct UIKitNoteTextEditorUndoSnapshot {
    let attributedText: NSAttributedString
    let selectedRange: NSRange
}

final class UIKitNoteTextEditorContainerView: UIView {
    final class DecorationView: UIView {
        weak var textView: UIKitNoteTextEditorSurface.AccessoryTextView?
        private let codeBlockLayer = CAShapeLayer()
        private let blockquoteLayer = CAShapeLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isUserInteractionEnabled = false
            isOpaque = false
            codeBlockLayer.fillColor = NoteTextAppearance.codeBlockBackgroundColor.cgColor
            blockquoteLayer.fillColor = NoteTextAppearance.blockquoteRuleColor.cgColor
            layer.addSublayer(codeBlockLayer)
            layer.addSublayer(blockquoteLayer)
            registerForAppearanceChanges()
        }

        @available(*, unavailable) required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func syncResolvedColors() {
            let traits = textView?.traitCollection ?? traitCollection
            codeBlockLayer.fillColor = NoteTextAppearance.codeBlockBackgroundColor
                .resolvedColor(with: traits)
                .cgColor
            blockquoteLayer.fillColor = NoteTextAppearance.blockquoteRuleColor
                .resolvedColor(with: traits)
                .cgColor
        }

        private func registerForAppearanceChanges() {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
                self.syncResolvedColors()
                self.refreshPaths()
            }
        }

        func refreshPaths() {
            guard let textView else { return }
            syncResolvedColors()
            let attributedText = textView.attributedText ?? NSAttributedString()
            guard attributedText.length > 0 else {
                codeBlockLayer.path = nil
                blockquoteLayer.path = nil
                return
            }

            let textContainerInset = CGSize(
                width: textView.textContainerInset.left,
                height: textView.textContainerInset.top
            )
            let codeBlockRects = NoteTextCodeBlockBackgroundLayout.detachedBlockRects(
                in: attributedText,
                containerWidth: textView.bounds.width,
                textContainerInset: textContainerInset
            )
            if codeBlockRects.isEmpty {
                codeBlockLayer.path = nil
            } else {
                let codeBlockPath = UIBezierPath()
                for blockRect in codeBlockRects {
                    codeBlockPath.append(
                        UIBezierPath(
                            roundedRect: blockRect,
                            cornerRadius: NoteTextAppearance.codeBlockCornerRadius
                        )
                    )
                }
                codeBlockLayer.frame = bounds
                codeBlockLayer.path = codeBlockPath.cgPath
            }

            let blockquoteRuleRects = NoteTextBlockquoteDecorationLayout.detachedRuleRects(
                in: attributedText,
                containerWidth: textView.bounds.width,
                textContainerInset: textContainerInset
            )
            if blockquoteRuleRects.isEmpty {
                blockquoteLayer.path = nil
            } else {
                let blockquotePath = UIBezierPath()
                for ruleRect in blockquoteRuleRects {
                    blockquotePath.append(UIBezierPath(roundedRect: ruleRect, cornerRadius: 1.5))
                }
                blockquoteLayer.frame = bounds
                blockquoteLayer.path = blockquotePath.cgPath
            }
        }
    }

    let textView: UIKitNoteTextEditorSurface.AccessoryTextView

    init(textView: UIKitNoteTextEditorSurface.AccessoryTextView) {
        self.textView = textView
        super.init(frame: .zero)
        backgroundColor = .clear
        clipsToBounds = true
        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@available(iOS 26.0, *)
extension UIKitNoteTextEditorSurface {
    class AccessoryTextView: UITextView {
        static let baseTextContainerInsets = UIEdgeInsets(
            top: NoteTextLayout.verticalPadding, left: NoteTextLayout.horizontalPadding,
            bottom: NoteTextLayout.verticalPadding, right: NoteTextLayout.horizontalPadding
        )

        var formattingAccessoryView: UIView?
        var formattingCommandsEnabled = false
        var onViewportSnapshotChange: ((CGPoint, NSRange, CGFloat?) -> Void)?
        var onBoldCommand: (() -> Void)?
        var onItalicCommand: (() -> Void)?
        var onUnderlineCommand: (() -> Void)?
        var onEscapeCommand: (() -> Void)?
        var onTitleCommand: (() -> Void)?
        var onHeadingCommand: (() -> Void)?
        var onSubheadingCommand: (() -> Void)?
        var onBodyCommand: (() -> Void)?
        var onDidMoveToWindow: ((AccessoryTextView) -> Void)?
        weak var decorationView: UIKitNoteTextEditorContainerView.DecorationView?
        var shouldAutofocus = false
        var hasScheduledAutofocus = false
        var suppressAutofocusReveal = false
        private var lastReportedViewportSnapshot: UIKitNoteTextEditorViewportSnapshot?
        var maxReadableContentWidth: CGFloat = .greatestFiniteMagnitude {
            didSet { setNeedsLayout() }
        }

        override init(frame: CGRect, textContainer: NSTextContainer?) {
            super.init(frame: frame, textContainer: textContainer)
            registerForAppearanceChanges()
        }

        @available(*, unavailable) required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var inputAccessoryView: UIView? {
            get { formattingAccessoryView }
            set { formattingAccessoryView = newValue }
        }

        override var contentOffset: CGPoint {
            didSet {
                reportViewportSnapshotIfNeeded()
                decorationView?.refreshPaths()
            }
        }

        override var contentSize: CGSize {
            didSet {
                syncDecorationViewFrame()
                decorationView?.refreshPaths()
            }
        }

        override var keyCommands: [UIKeyCommand]? {
            var commands = super.keyCommands ?? []
            if formattingCommandsEnabled {
                commands.append(contentsOf: [
                    UIKeyCommand(input: "t", modifierFlags: [.command, .shift], action: #selector(handleTitleCommand)),
                    UIKeyCommand(input: "h", modifierFlags: [.command, .shift], action: #selector(handleHeadingCommand)),
                    UIKeyCommand(input: "j", modifierFlags: [.command, .shift], action: #selector(handleSubheadingCommand)),
                    UIKeyCommand(input: "b", modifierFlags: [.command, .shift], action: #selector(handleBodyCommand)),
                    UIKeyCommand(input: "b", modifierFlags: [.command], action: #selector(handleBoldCommand)),
                    UIKeyCommand(input: "i", modifierFlags: [.command], action: #selector(handleItalicCommand)),
                    UIKeyCommand(input: "u", modifierFlags: [.command], action: #selector(handleUnderlineCommand))
                ])
            }
            if onEscapeCommand != nil {
                commands.append(
                    UIKeyCommand(
                        input: UIKeyCommand.inputEscape,
                        modifierFlags: [],
                        action: #selector(handleEscapeCommand)
                    )
                )
            }
            return commands.isEmpty ? nil : commands
        }

        @objc private func handleTitleCommand() { onTitleCommand?() }
        @objc private func handleHeadingCommand() { onHeadingCommand?() }
        @objc private func handleSubheadingCommand() { onSubheadingCommand?() }
        @objc private func handleBodyCommand() { onBodyCommand?() }
        @objc private func handleBoldCommand() { onBoldCommand?() }
        @objc private func handleItalicCommand() { onItalicCommand?() }
        @objc private func handleUnderlineCommand() { onUnderlineCommand?() }
        @objc func handleEscapeCommand() { onEscapeCommand?() }

        override func layoutSubviews() {
            super.layoutSubviews()
            updateTextContainerInsets()
            updateViewportInsets()
            syncDecorationViewFrame()
            decorationView?.refreshPaths()
            reportViewportSnapshotIfNeeded()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onDidMoveToWindow?(self)
        }

        private func registerForAppearanceChanges() {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: AccessoryTextView, _) in
                self.decorationView?.refreshPaths()
            }
        }

        override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
            if suppressAutofocusReveal, animated { return }
            super.setContentOffset(contentOffset, animated: animated)
        }

        override func scrollRectToVisible(_ rect: CGRect, animated: Bool) {
            if suppressAutofocusReveal, animated { return }
            super.scrollRectToVisible(rect, animated: animated)
        }

        override func scrollRangeToVisible(_ range: NSRange) {
            if suppressAutofocusReveal { return }
            super.scrollRangeToVisible(range)
        }

        func reportViewportSnapshotIfNeeded(force: Bool = false) {
            let snapshot = UIKitNoteTextEditorViewportSnapshot(
                contentOffset: contentOffset,
                selectedRange: selectedRange,
                selectionViewportAnchorY: currentSelectionViewportAnchorY()
            )
            guard force || snapshot != lastReportedViewportSnapshot else { return }
            lastReportedViewportSnapshot = snapshot
            onViewportSnapshotChange?(
                snapshot.contentOffset,
                snapshot.selectedRange,
                snapshot.selectionViewportAnchorY
            )
        }

        func invalidateCodeBlockBackgroundLayout() {
            decorationView?.refreshPaths()
        }

        private func syncDecorationViewFrame() {
            guard let decorationView else { return }
            let resolvedHeight = max(bounds.height, contentSize.height)
            let resolvedFrame = CGRect(
                x: 0,
                y: 0,
                width: bounds.width,
                height: resolvedHeight
            )
            guard decorationView.frame != resolvedFrame else { return }
            decorationView.frame = resolvedFrame
            decorationView.refreshPaths()
        }
    }
}
#endif
