// swiftlint:disable file_length
#if os(iOS)
import SwiftUI
import UIKit
// swiftlint:disable type_body_length

struct UIKitNoteTextEditorRenderSignature: Equatable {
    let renderGeneration: UInt64
    let baseFontSize: CGFloat
}

private struct UIKitNoteTextEditorViewportSnapshot: Equatable {
    let contentOffset: CGPoint
    let selectedRange: NSRange
    let selectionViewportAnchorY: CGFloat?
}

private struct UIKitNoteTextEditorUndoSnapshot {
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

        override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection)
            syncResolvedColors()
            refreshPaths()
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
struct UIKitNoteTextEditorSurface: UIViewRepresentable {
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

        override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection)
            decorationView?.refreshPaths()
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
    @ObservedObject var viewModel: NativeNoteEditorViewModel
    let maxContentWidth: CGFloat
    let isEditable: Bool
    let shouldAutofocus: Bool
    let formattingBarConfiguration: NoteFormattingBarConfiguration?
    let formattingBarPresentation: NoteFormattingBarPresentation
    let pendingSelectionTarget: NotesEditorViewModel.PendingEditSelectionTarget?; let pendingSelectionViewportAnchorY: CGFloat?
    let onPendingSelectionTargetApplied: ((AccessoryTextView) -> Void)?; let onDidBeginEditing: ((AccessoryTextView) -> Void)?
    let onViewportSnapshotChange: ((CGPoint, NSRange, CGFloat?) -> Void)?
    let onTextViewReady: ((AccessoryTextView) -> Void)?
    let makeTextView: (() -> AccessoryTextView)?
    let onEscape: (() -> Void)?

    init(
        viewModel: NativeNoteEditorViewModel,
        maxContentWidth: CGFloat,
        isEditable: Bool,
        shouldAutofocus: Bool = true,
        formattingBarConfiguration: NoteFormattingBarConfiguration? = nil,
        formattingBarPresentation: NoteFormattingBarPresentation,
        pendingSelectionTarget: NotesEditorViewModel.PendingEditSelectionTarget? = nil,
        pendingSelectionViewportAnchorY: CGFloat? = nil,
        onPendingSelectionTargetApplied: ((AccessoryTextView) -> Void)? = nil,
        onDidBeginEditing: ((AccessoryTextView) -> Void)? = nil,
        onViewportSnapshotChange: ((CGPoint, NSRange, CGFloat?) -> Void)? = nil,
        onTextViewReady: ((AccessoryTextView) -> Void)? = nil,
        makeTextView: (() -> AccessoryTextView)? = nil,
        onEscape: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.maxContentWidth = maxContentWidth
        self.isEditable = isEditable
        self.shouldAutofocus = shouldAutofocus
        self.formattingBarConfiguration = formattingBarConfiguration
        self.formattingBarPresentation = formattingBarPresentation
        self.pendingSelectionTarget = pendingSelectionTarget
        self.pendingSelectionViewportAnchorY = pendingSelectionViewportAnchorY
        self.onPendingSelectionTargetApplied = onPendingSelectionTargetApplied
        self.onDidBeginEditing = onDidBeginEditing
        self.onViewportSnapshotChange = onViewportSnapshotChange
        self.onTextViewReady = onTextViewReady
        self.makeTextView = makeTextView
        self.onEscape = onEscape
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> UIKitNoteTextEditorContainerView {
        let textView = makeTextView?() ?? AccessoryTextView()
        textView.isEditable = isEditable
        textView.allowsEditingTextAttributes = false
        textView.shouldAutofocus = isEditable && shouldAutofocus
        textView.backgroundColor = .clear
        textView.textColor = .label
        textView.tintColor = NoteTextAppearance.caretTintColor
        textView.accessibilityIdentifier = "notes-editor-text-view"
        textView.textContainer.lineFragmentPadding = 0
        textView.maxReadableContentWidth = maxContentWidth
        textView.onViewportSnapshotChange = onViewportSnapshotChange
        textView.onEscapeCommand = onEscape
        textView.onDidMoveToWindow = { attachedTextView in
            handleTextViewDidMoveToWindow(attachedTextView)
        }
        textView.delegate = context.coordinator
        textView.textFormattingConfiguration = nil
        if shouldShowFormattingAccessory, let formattingBarConfiguration {
            textView.formattingAccessoryView = makeFormattingAccessoryView(
                configuration: formattingBarConfiguration
            )
        }
        let decorationView = UIKitNoteTextEditorContainerView.DecorationView()
        decorationView.textView = textView
        textView.insertSubview(decorationView, at: 0)
        textView.decorationView = decorationView
        let containerView = UIKitNoteTextEditorContainerView(textView: textView)
        onTextViewReady?(textView)
        return containerView
    }

    func updateUIView(_ containerView: UIKitNoteTextEditorContainerView, context: Context) {
        let textView = containerView.textView
        onTextViewReady?(textView)
        context.coordinator.onDidBeginEditing = onDidBeginEditing
        textView.isEditable = isEditable
        textView.shouldAutofocus = isEditable && shouldAutofocus
        textView.maxReadableContentWidth = maxContentWidth
        textView.onViewportSnapshotChange = onViewportSnapshotChange
        textView.onEscapeCommand = onEscape
        textView.onDidMoveToWindow = { attachedTextView in
            handleTextViewDidMoveToWindow(attachedTextView)
        }
        if pendingSelectionViewportAnchorY != nil, textView.shouldAutofocus, !textView.isFirstResponder {
            textView.suppressAutofocusReveal = true
        }
        let needsAccessoryReload = configureFormattingUI(
            for: textView,
            configuration: formattingBarConfiguration
        )
        if needsAccessoryReload, textView.isFirstResponder {
            textView.reloadInputViews()
        }
        let renderSignature = UIKitNoteTextEditorRenderSignature(
            renderGeneration: viewModel.renderGeneration,
            baseFontSize: viewModel.baseFontSize
        )
        let selectedRange = resolvedSelectedRange(
            pendingSelectionTarget: pendingSelectionTarget,
            textView: textView,
            coordinator: context.coordinator
        )
        let isProgrammaticRenderUpdate = context.coordinator.lastAppliedRenderSignature != renderSignature
        applyRenderedTextIfNeeded(
            to: textView,
            coordinator: context.coordinator,
            renderSignature: renderSignature,
            isProgrammaticRenderUpdate: isProgrammaticRenderUpdate
        )
        applySelectionIfNeeded(
            to: textView,
            coordinator: context.coordinator,
            selectedRange: selectedRange
        )
        scheduleAutofocusIfNeeded(for: textView)
        acknowledgePendingSelectionTargetIfNeeded(
            pendingSelectionTarget,
            selectedRange: selectedRange,
            textView: textView,
            coordinator: context.coordinator
        )

        let typingAttributes = bridgedTypingAttributes(from: viewModel.attributedContent)
        if NSDictionary(dictionary: textView.typingAttributes).isEqual(to: typingAttributes) == false {
            textView.typingAttributes = typingAttributes
        }
    }

    static func dismantleUIView(_ containerView: UIKitNoteTextEditorContainerView, coordinator: Void) {
        let textView = containerView.textView
        if textView.isFirstResponder {
            _ = textView.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        let viewModel: NativeNoteEditorViewModel
        var isApplyingProgrammaticText = false, isApplyingProgrammaticSelection = false
        var lastAppliedRenderSignature: UIKitNoteTextEditorRenderSignature?
        var acknowledgedPendingSelectionTarget: NotesEditorViewModel.PendingEditSelectionTarget?
        var onDidBeginEditing: ((AccessoryTextView) -> Void)?

        init(viewModel: NativeNoteEditorViewModel) {
            self.viewModel = viewModel
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingProgrammaticText else { return }
            (textView as? AccessoryTextView)?.invalidateCodeBlockBackgroundLayout()
            let document = viewModel.currentPersistenceSnapshot().document

            let attributedText = SelectableNoteReadView.expandingChecklistEditorMarkers(
                in: textView.attributedText,
                document: document
            )
            let selectedRange = SelectableNoteReadView.logicalEditorSelectedRange(
                fromDisplaySelectedRange: textView.selectedRange,
                in: textView.attributedText,
                document: document
            )
            DispatchQueue.main.async {
                self.viewModel.replaceAttributedContentFromLiveTextView(
                    attributedText,
                    selectedUTF16Range: selectedRange
                )
                self.lastAppliedRenderSignature = UIKitNoteTextEditorRenderSignature(
                    renderGeneration: self.viewModel.renderGeneration,
                    baseFontSize: self.viewModel.baseFontSize
                )
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingProgrammaticText, !isApplyingProgrammaticSelection else { return }
            guard textView.isFirstResponder else { return }
            let document = viewModel.currentPersistenceSnapshot().document

            let logicalSelectedRange = SelectableNoteReadView.logicalEditorSelectedRange(
                fromDisplaySelectedRange: textView.selectedRange,
                in: textView.attributedText,
                document: document
            )
            let selection = viewModel.selection(
                fromUTF16Range: logicalSelectedRange,
                in: viewModel.attributedContent
            )
            if selection != viewModel.selection {
                viewModel.selection = selection
                viewModel.handleSelectionChange()
            }
            (textView as? AccessoryTextView)?.reportViewportSnapshotIfNeeded(force: true)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            guard let textView = textView as? AccessoryTextView else { return }
            onDidBeginEditing?(textView)
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            guard viewModel.shouldHandleStructuralTextReplacement(text) else { return true }
            let document = viewModel.currentPersistenceSnapshot().document

            let logicalRange = SelectableNoteReadView.logicalEditorSelectedRange(
                fromDisplaySelectedRange: range,
                in: textView.attributedText,
                document: document
            )
            let selection = viewModel.selection(
                fromUTF16Range: logicalRange,
                in: viewModel.attributedContent
            )
            if selection != viewModel.selection {
                viewModel.selection = selection
                viewModel.handleSelectionChange()
            }
            let undoSnapshot = literalUndoSnapshot(
                in: textView,
                selectedRange: range,
                replacementText: text
            )
            guard viewModel.handleTextReplacement(text) else { return true }

            if let undoSnapshot {
                registerUndoSnapshot(undoSnapshot, on: textView)
            }
            applyCurrentEditorState(to: textView)
            return false
        }

        private func applyCurrentEditorState(to textView: UITextView) {
            let bridgedText = SelectableNoteReadView.bridgedPlatformEditorAttributedString(
                from: viewModel.attributedContent,
                document: viewModel.currentPersistenceSnapshot().document,
                baseFontSize: viewModel.baseFontSize
            )
            isApplyingProgrammaticText = true
            textView.textStorage.setAttributedString(bridgedText)
            isApplyingProgrammaticText = false
            (textView as? AccessoryTextView)?.invalidateCodeBlockBackgroundLayout()
            lastAppliedRenderSignature = UIKitNoteTextEditorRenderSignature(
                renderGeneration: viewModel.renderGeneration,
                baseFontSize: viewModel.baseFontSize
            )

            isApplyingProgrammaticSelection = true
            textView.selectedRange = SelectableNoteReadView.editorDisplaySelectedRange(
                in: viewModel.currentPersistenceSnapshot().document,
                logicalSelectedRange: viewModel.utf16SelectedRange(in: viewModel.attributedContent)
            )
            isApplyingProgrammaticSelection = false

            var sample = AttributedString("x")
            let sampleRange = sample.startIndex..<sample.endIndex
            sample[sampleRange].mergeAttributes(viewModel.typingAttributesForInsertion(in: viewModel.attributedContent))
            let bridgedTypingSample = SelectableNoteReadView.bridgedPlatformAttributedString(
                from: sample,
                baseFontSize: viewModel.baseFontSize
            )
            textView.typingAttributes = bridgedTypingSample.attributes(at: 0, effectiveRange: nil)
        }

        private func literalUndoSnapshot(
            in textView: UITextView,
            selectedRange: NSRange,
            replacementText: String
        ) -> UIKitNoteTextEditorUndoSnapshot? {
            guard replacementText == " " else { return nil }

            let updatedText = NSMutableAttributedString(attributedString: textView.attributedText)
            let insertedText = NSAttributedString(
                string: replacementText,
                attributes: textView.typingAttributes
            )
            updatedText.replaceCharacters(in: selectedRange, with: insertedText)
            let updatedSelection = NSRange(
                location: selectedRange.location + insertedText.length,
                length: 0
            )
            return UIKitNoteTextEditorUndoSnapshot(
                attributedText: SelectableNoteReadView.expandingChecklistEditorMarkers(
                    in: updatedText,
                    document: viewModel.currentPersistenceSnapshot().document
                ),
                selectedRange: SelectableNoteReadView.logicalEditorSelectedRange(
                    fromDisplaySelectedRange: updatedSelection,
                    in: updatedText,
                    document: viewModel.currentPersistenceSnapshot().document
                )
            )
        }

        private func registerUndoSnapshot(
            _ snapshot: UIKitNoteTextEditorUndoSnapshot,
            on textView: UITextView
        ) {
            textView.undoManager?.registerUndo(withTarget: self) { target in
                target.restoreUndoSnapshot(snapshot, on: textView)
            }
        }

        private func restoreUndoSnapshot(
            _ snapshot: UIKitNoteTextEditorUndoSnapshot,
            on textView: UITextView
        ) {
            let redoSnapshot = UIKitNoteTextEditorUndoSnapshot(
                attributedText: SelectableNoteReadView.expandingChecklistEditorMarkers(
                    in: textView.attributedText,
                    document: viewModel.currentPersistenceSnapshot().document
                ),
                selectedRange: SelectableNoteReadView.logicalEditorSelectedRange(
                    fromDisplaySelectedRange: textView.selectedRange,
                    in: textView.attributedText,
                    document: viewModel.currentPersistenceSnapshot().document
                )
            )
            viewModel.replaceAttributedContent(
                snapshot.attributedText,
                selectedUTF16Range: snapshot.selectedRange
            )
            registerUndoSnapshot(redoSnapshot, on: textView)
            applyCurrentEditorState(to: textView)
        }
    }
}

// swiftlint:enable type_body_length
#endif
