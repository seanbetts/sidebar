import SwiftUI
import sideBarShared
#if os(macOS)
import AppKit

@available(iOS 26.0, macOS 26.0, *)
extension SelectableNoteReadView {
    private struct ReadActivationLineMetrics {
        let fragmentRect: CGRect
        let usedRect: CGRect
        let endCharacterOffset: Int
    }

    private static func visualLineEndOffset(
        in layoutManager: NSLayoutManager,
        glyphRange: NSRange,
        plainText: NSString
    ) -> Int {
        let characterRange = layoutManager.characterRange(
            forGlyphRange: glyphRange,
            actualGlyphRange: nil
        )
        var endOffset = min(characterRange.location + characterRange.length, plainText.length)

        while endOffset > characterRange.location,
              let scalar = UnicodeScalar(plainText.character(at: endOffset - 1)),
              CharacterSet.newlines.contains(scalar) {
            endOffset -= 1
        }

        return endOffset
    }

    private static func lineMetrics(
        in layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        plainText: NSString,
        lineY: CGFloat
    ) -> ReadActivationLineMetrics? {
        let fullGlyphRange = layoutManager.glyphRange(for: textContainer)
        var result: ReadActivationLineMetrics?
        layoutManager.enumerateLineFragments(forGlyphRange: fullGlyphRange) { lineFragmentRect, usedRect, _, glyphRange, stop in
            let normalizedFragmentRect = lineFragmentRect.standardized.insetBy(dx: 0, dy: -0.5)
            guard normalizedFragmentRect.minY <= lineY, lineY <= normalizedFragmentRect.maxY else {
                return
            }
            result = ReadActivationLineMetrics(
                fragmentRect: lineFragmentRect,
                usedRect: usedRect,
                endCharacterOffset: visualLineEndOffset(
                    in: layoutManager,
                    glyphRange: glyphRange,
                    plainText: plainText
                )
            )
            stop.pointee = ObjCBool(true)
        }
        return result
    }

    static func makePlatformTextView(
        attributedContent: NSAttributedString,
        onActivateEditing: ((ReadActivationTarget) -> Void)? = nil
    ) -> NSTextView {
        makePlatformTextView(
            attributedContent: attributedContent,
            document: NotesSemanticDocument(version: NotesSemanticDocument.currentVersion, blocks: []),
            onActivateEditing: onActivateEditing
        )
    }

    static func makePlatformTextView(
        attributedContent: NSAttributedString,
        document: NotesSemanticDocument,
        onActivateEditing: ((ReadActivationTarget) -> Void)? = nil,
        onToggleChecklistItem: ChecklistToggleHandler? = nil
    ) -> NSTextView {
        let textView = SelectableNoteReadTextView()
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.identifier = NSUserInterfaceItemIdentifier("notes-read-text-view")
        textView.setAccessibilityLabel("Notes read surface")
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.heightTracksTextView = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        textView.document = document
        textView.onActivateEditing = onActivateEditing
        textView.onToggleChecklistItem = onToggleChecklistItem
        textView.installActivationClickRecognizerIfNeeded()
        textView.textStorage?.setAttributedString(attributedContent)
        return textView
    }

    static func characterOffsetForEditingActivation(
        in textView: NSTextView,
        at point: NSPoint
    ) -> Int? {
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return nil }
        textView.layoutSubtreeIfNeeded()
        layoutManager.ensureLayout(for: textContainer)
        let plainText = textView.string as NSString
        guard plainText.length > 0 else { return 0 }
        let containerPoint = NSPoint(
            x: point.x - textView.textContainerInset.width,
            y: point.y - textView.textContainerInset.height
        )
        if containerPoint.y > layoutManager.usedRect(for: textContainer).maxY { return plainText.length }
        if let line = lineMetrics(
            in: layoutManager,
            textContainer: textContainer,
            plainText: plainText,
            lineY: containerPoint.y
        ),
           containerPoint.x > line.usedRect.maxX {
            return line.endCharacterOffset
        }

        let characterIndex = layoutManager.characterIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        return min(max(characterIndex, 0), plainText.length)
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct PlatformSelectableNoteReadView: NSViewRepresentable {
    let attributedContent: NSAttributedString
    let document: NotesSemanticDocument
    let maxReadableContentWidth: CGFloat
    let initialViewportOffset: CGPoint?
    let initialViewportAnchorTarget: SelectableNoteReadView.ReadActivationTarget?
    let initialViewportAnchorY: CGFloat?
    let presentationGeneration: UInt64
    let onActivateEditing: ((SelectableNoteReadView.ReadActivationTarget) -> Void)?
    let onActivateEditingWithViewport: ((SelectableNoteReadView.ReadActivationTarget, CGFloat?) -> Void)?
    let onToggleChecklistItem: SelectableNoteReadView.ChecklistToggleHandler?
    let onViewportOffsetChange: ((CGPoint) -> Void)?
    let onInitialViewportRestorationApplied: (() -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let textView = SelectableNoteReadView.makePlatformTextView(
            attributedContent: attributedContent,
            document: document,
            onActivateEditing: onActivateEditing,
            onToggleChecklistItem: onToggleChecklistItem
        )
        guard let readTextView = textView as? SelectableNoteReadTextView else {
            preconditionFailure("Expected SelectableNoteReadTextView for macOS read surface")
        }
        readTextView.maxReadableContentWidth = maxReadableContentWidth
        readTextView.presentationGeneration = presentationGeneration
        readTextView.onViewportOffsetChange = onViewportOffsetChange
        readTextView.onInitialViewportRestorationApplied = onInitialViewportRestorationApplied
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = readTextView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? SelectableNoteReadTextView else {
            return
        }
        textView.maxReadableContentWidth = maxReadableContentWidth
        textView.presentationGeneration = presentationGeneration
        textView.document = document
        textView.onActivateEditing = onActivateEditing
        textView.onToggleChecklistItem = onToggleChecklistItem
        textView.onViewportOffsetChange = onViewportOffsetChange
        textView.onInitialViewportRestorationApplied = onInitialViewportRestorationApplied
        if textView.textStorage?.isEqual(to: attributedContent) == false {
            textView.textStorage?.setAttributedString(attributedContent)
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: ()) {
        guard let textView = scrollView.documentView as? SelectableNoteReadTextView else {
            return
        }
        textView.document = NotesSemanticDocument(version: NotesSemanticDocument.currentVersion, blocks: [])
        textView.onActivateEditing = nil
        textView.onToggleChecklistItem = nil
        textView.onViewportOffsetChange = nil
        textView.onInitialViewportRestorationApplied = nil
        scrollView.documentView = nil
    }
}

#endif
