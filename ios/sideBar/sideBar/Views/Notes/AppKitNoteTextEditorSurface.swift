#if os(macOS)
import AppKit
import SwiftUI

private struct AppKitNoteTextEditorUndoSnapshot {
    let attributedText: NSAttributedString
    let selectedRange: NSRange
}

@available(iOS 26.0, macOS 26.0, *)
struct AppKitNoteTextEditorSurface: NSViewRepresentable {
    struct RenderSignature: Equatable {
        let renderGeneration: UInt64
        let baseFontSize: CGFloat
    }

    final class EditorTextView: NSTextView {
        private static let baseTextContainerInset = NSSize(
            width: NoteTextLayout.horizontalPadding,
            height: NoteTextLayout.verticalPadding
        )

        var shouldAutofocus = false
        var onEscapeCommand: (() -> Void)?
        var onInitialPresentationReady: (() -> Void)?
        private var didScheduleAutofocus = false
        private var didReportInitialPresentationReady = false
        var maxReadableContentWidth: CGFloat = .greatestFiniteMagnitude {
            didSet { needsLayout = true }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateTextContainerInset()
            emitTransitionTrace("viewDidMoveToWindow")
            scheduleAutofocusIfNeeded()
            scheduleInitialPresentationReadyIfNeeded()
        }

        override func layout() {
            super.layout()
            updateTextContainerInset()
            emitTransitionTrace("layout")
            scheduleInitialPresentationReadyIfNeeded()
            needsDisplay = true
        }

        override func draw(_ dirtyRect: NSRect) {
            drawCodeBlockBackgrounds(in: dirtyRect)
            super.draw(dirtyRect)
        }

        override func cancelOperation(_ sender: Any?) {
            if let onEscapeCommand {
                if window?.firstResponder === self {
                    window?.makeFirstResponder(nil)
                }
                onEscapeCommand()
                return
            }
            super.cancelOperation(sender)
        }

        func scheduleAutofocusIfNeeded() {
            guard shouldAutofocus, !didScheduleAutofocus, let window else { return }
            didScheduleAutofocus = true
            emitTransitionTrace("scheduleAutofocusIfNeeded.queued")
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self,
                      self.shouldAutofocus,
                      let window,
                      self.window === window,
                      window.firstResponder !== self else {
                    return
                }
                window.makeFirstResponder(self)
                self.emitTransitionTrace("scheduleAutofocusIfNeeded.applied")
                self.scheduleInitialPresentationReadyIfNeeded()
            }
        }

        private func updateTextContainerInset() {
            let extraHorizontalInset = max((bounds.width - maxReadableContentWidth) / 2, 0)
            let resolvedInset = NSSize(
                width: Self.baseTextContainerInset.width + extraHorizontalInset,
                height: Self.baseTextContainerInset.height
            )
            guard textContainerInset != resolvedInset else { return }
            let previousInset = textContainerInset
            textContainerInset = resolvedInset
            NotesTransitionDebugTrace.log(
                "appkitEditor.textContainerInsetUpdated",
                details: [
                    "previous=\(NotesTransitionDebugTrace.format(previousInset))",
                    "resolved=\(NotesTransitionDebugTrace.format(resolvedInset))",
                    "bounds=\(NotesTransitionDebugTrace.format(bounds))",
                    "maxReadableWidth=\(NotesTransitionDebugTrace.format(maxReadableContentWidth))"
                ].joined(separator: " ")
            )
        }

        private func drawCodeBlockBackgrounds(in dirtyRect: NSRect) {
            guard let textStorage,
                  let layoutManager,
                  let textContainer else { return }
            let backgroundRects = NoteTextCodeBlockBackgroundLayout.blockRects(
                in: textStorage,
                layoutManager: layoutManager,
                textContainer: textContainer,
                textContainerInset: textContainerInset
            )
            guard backgroundRects.isEmpty == false else { return }

            NoteTextAppearance.codeBlockBackgroundColor.setFill()
            for backgroundRect in backgroundRects where backgroundRect.intersects(dirtyRect) {
                NSBezierPath(
                    roundedRect: backgroundRect,
                    xRadius: NoteTextAppearance.codeBlockCornerRadius,
                    yRadius: NoteTextAppearance.codeBlockCornerRadius
                ).fill()
            }
        }
    }

    @ObservedObject var viewModel: NativeNoteEditorViewModel
    let maxContentWidth: CGFloat
    let isEditable: Bool
    let shouldAutofocus: Bool
    let onInitialPresentationReady: (() -> Void)?
    let onEscape: (() -> Void)?

    init(
        viewModel: NativeNoteEditorViewModel,
        maxContentWidth: CGFloat,
        isEditable: Bool,
        shouldAutofocus: Bool = true,
        onInitialPresentationReady: (() -> Void)? = nil,
        onEscape: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.maxContentWidth = maxContentWidth
        self.isEditable = isEditable
        self.shouldAutofocus = shouldAutofocus
        self.onInitialPresentationReady = onInitialPresentationReady
        self.onEscape = onEscape
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let viewModel: NativeNoteEditorViewModel
        weak var textView: NSTextView?
        var isApplyingProgrammaticText = false
        var isApplyingProgrammaticSelection = false
        var lastAppliedRenderSignature: RenderSignature?

        init(viewModel: NativeNoteEditorViewModel) {
            self.viewModel = viewModel
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingProgrammaticText,
                  let textView = notification.object as? NSTextView else {
                return
            }
            let document = viewModel.currentPersistenceSnapshot().document

            let attributedText = NSAttributedString(attributedString: textView.attributedString())
            let selectedRange = SelectableNoteReadView.logicalEditorSelectedRange(
                fromDisplaySelectedRange: textView.selectedRange(),
                in: textView.attributedString(),
                document: document
            )
            DispatchQueue.main.async {
                self.viewModel.replaceAttributedContent(
                    SelectableNoteReadView.expandingChecklistEditorMarkers(
                        in: attributedText,
                        document: document
                    ),
                    selectedUTF16Range: selectedRange
                )
                self.lastAppliedRenderSignature = RenderSignature(
                    renderGeneration: self.viewModel.renderGeneration,
                    baseFontSize: self.viewModel.baseFontSize
                )
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingProgrammaticText,
                  !isApplyingProgrammaticSelection,
                  let textView = notification.object as? NSTextView else {
                return
            }
            let document = viewModel.currentPersistenceSnapshot().document

            let logicalSelectedRange = SelectableNoteReadView.logicalEditorSelectedRange(
                fromDisplaySelectedRange: textView.selectedRange(),
                in: textView.attributedString(),
                document: document
            )
            let selection = viewModel.selection(
                fromUTF16Range: logicalSelectedRange,
                in: viewModel.attributedContent
            )
            guard selection != viewModel.selection else { return }
            viewModel.selection = selection
            viewModel.handleSelectionChange()
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                return handleStructuralReplacement(
                    in: textView,
                    selectedRange: textView.selectedRange(),
                    replacementText: "\n"
                )
            case #selector(NSResponder.deleteBackward(_:)):
                return handleStructuralReplacement(
                    in: textView,
                    selectedRange: textView.selectedRange(),
                    replacementText: ""
                )
            default:
                return false
            }
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard let replacementString else { return true }

            if handleStructuralReplacement(
                in: textView,
                selectedRange: affectedCharRange,
                replacementText: replacementString
            ) {
                return false
            }

            return true
        }

        private func handleStructuralReplacement(
            in textView: NSTextView,
            selectedRange: NSRange,
            replacementText: String
        ) -> Bool {
            let document = viewModel.currentPersistenceSnapshot().document
            let logicalSelectedRange = SelectableNoteReadView.logicalEditorSelectedRange(
                fromDisplaySelectedRange: selectedRange,
                in: textView.attributedString(),
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

            guard viewModel.shouldHandleStructuralTextReplacement(replacementText) else { return false }
            let undoSnapshot = literalUndoSnapshot(
                in: textView,
                selectedRange: selectedRange,
                replacementText: replacementText
            )
            guard viewModel.handleTextReplacement(replacementText) else { return false }

            if let undoSnapshot {
                registerUndoSnapshot(undoSnapshot, on: textView)
            }
            applyCurrentEditorState(to: textView)
            return true
        }

        private func applyCurrentEditorState(to textView: NSTextView) {
            let bridgedText = SelectableNoteReadView.bridgedPlatformEditorAttributedString(
                from: viewModel.attributedContent,
                document: viewModel.currentPersistenceSnapshot().document,
                baseFontSize: viewModel.baseFontSize
            )
            isApplyingProgrammaticText = true
            textView.textStorage?.setAttributedString(bridgedText)
            isApplyingProgrammaticText = false
            lastAppliedRenderSignature = RenderSignature(
                renderGeneration: viewModel.renderGeneration,
                baseFontSize: viewModel.baseFontSize
            )

            isApplyingProgrammaticSelection = true
            textView.setSelectedRange(
                SelectableNoteReadView.editorDisplaySelectedRange(
                    in: viewModel.currentPersistenceSnapshot().document,
                    logicalSelectedRange: viewModel.utf16SelectedRange(in: viewModel.attributedContent)
                )
            )
            isApplyingProgrammaticSelection = false

            var sample = AttributedString("x")
            let range = sample.startIndex..<sample.endIndex
            sample[range].mergeAttributes(viewModel.typingAttributesForInsertion(in: viewModel.attributedContent))
            let bridgedTypingSample = SelectableNoteReadView.bridgedPlatformAttributedString(
                from: sample,
                baseFontSize: viewModel.baseFontSize
            )
            textView.typingAttributes = bridgedTypingSample.attributes(at: 0, effectiveRange: nil)
        }

        private func literalUndoSnapshot(
            in textView: NSTextView,
            selectedRange: NSRange,
            replacementText: String
        ) -> AppKitNoteTextEditorUndoSnapshot? {
            guard replacementText == " " else { return nil }

            let updatedText = NSMutableAttributedString(
                attributedString: textView.attributedString()
            )
            let insertedText = NSAttributedString(
                string: replacementText,
                attributes: textView.typingAttributes
            )
            updatedText.replaceCharacters(in: selectedRange, with: insertedText)
            let updatedSelection = NSRange(
                location: selectedRange.location + insertedText.length,
                length: 0
            )
            return AppKitNoteTextEditorUndoSnapshot(
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
            _ snapshot: AppKitNoteTextEditorUndoSnapshot,
            on textView: NSTextView
        ) {
            textView.undoManager?.registerUndo(withTarget: self) { target in
                target.restoreUndoSnapshot(snapshot, on: textView)
            }
        }

        private func restoreUndoSnapshot(
            _ snapshot: AppKitNoteTextEditorUndoSnapshot,
            on textView: NSTextView
        ) {
            let redoSnapshot = AppKitNoteTextEditorUndoSnapshot(
                attributedText: SelectableNoteReadView.expandingChecklistEditorMarkers(
                    in: textView.attributedString(),
                    document: viewModel.currentPersistenceSnapshot().document
                ),
                selectedRange: SelectableNoteReadView.logicalEditorSelectedRange(
                    fromDisplaySelectedRange: textView.selectedRange(),
                    in: textView.attributedString(),
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
extension AppKitNoteTextEditorSurface {
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }
}

extension AppKitNoteTextEditorSurface.EditorTextView {
    func scheduleInitialPresentationReadyIfNeeded() {
        guard !didReportInitialPresentationReady,
              window != nil,
              bounds.width > 0,
              bounds.height > 0 else {
            NotesTransitionDebugTrace.log(
                "appkitEditor.initialPresentationReady.deferred",
                details: transitionTraceSummary()
            )
            return
        }
        if shouldAutofocus, window?.firstResponder !== self {
            NotesTransitionDebugTrace.log(
                "appkitEditor.initialPresentationReady.waitingForFocus",
                details: transitionTraceSummary()
            )
            DispatchQueue.main.async { [weak self] in
                self?.scheduleInitialPresentationReadyIfNeeded()
            }
            return
        }
        didReportInitialPresentationReady = true
        NotesTransitionDebugTrace.log(
            "appkitEditor.initialPresentationReady.reported",
            details: transitionTraceSummary()
        )
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            self.onInitialPresentationReady?()
        }
    }

    func emitTransitionTrace(_ event: String) {
        NotesTransitionDebugTrace.log(
            "appkitEditor.\(event)",
            details: transitionTraceSummary()
        )
    }

    func transitionTraceSummary() -> String {
        let containerSize = textContainer?.containerSize
        let visibleRect = enclosingScrollView?.contentView.documentVisibleRect
        return [
            "bounds=\(NotesTransitionDebugTrace.format(bounds))",
            "visibleRect=\(NotesTransitionDebugTrace.format(visibleRect))",
            "inset=\(NotesTransitionDebugTrace.format(textContainerInset))",
            "containerSize=\(NotesTransitionDebugTrace.format(containerSize))",
            "windowAttached=\(window != nil)",
            "isFirstResponder=\(window?.firstResponder === self)",
            "shouldAutofocus=\(shouldAutofocus)",
            "didScheduleAutofocus=\(didScheduleAutofocus)",
            "didReportReady=\(didReportInitialPresentationReady)"
        ].joined(separator: " ")
    }
}
#endif
