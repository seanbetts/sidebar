import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@available(iOS 26.0, macOS 26.0, *)
struct SelectableNoteReadView: View {
    let document: NotesSemanticDocument
    let maxContentWidth: CGFloat
    var onActivateEditing: (() -> Void)?

    var body: some View {
        PlatformSelectableNoteReadView(
            attributedContent: Self.makeAttributedContent(from: document),
            onActivateEditing: onActivateEditing
        )
        .frame(maxWidth: maxContentWidth, maxHeight: .infinity, alignment: .topLeading)
    }

    static func makeAttributedContent(
        from document: NotesSemanticDocument,
        baseFontSize: CGFloat = NoteTextTypography.defaultBodyFontSize
    ) -> AttributedString {
        NotesAttributedDocumentCodec.readAttributedString(
            from: document,
            baseFontSize: baseFontSize
        )
    }

    #if os(macOS)
    static func makePlatformTextView(
        attributedContent: AttributedString,
        onActivateEditing: (() -> Void)? = nil
    ) -> NSTextView {
        let textView = SelectableNoteReadTextView()
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.textContainerInset = NSSize(
            width: NoteTextLayout.horizontalPadding,
            height: NoteTextLayout.verticalPadding
        )
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.autoresizingMask = [.width]
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        textView.onActivateEditing = onActivateEditing
        textView.textStorage?.setAttributedString(NSAttributedString(attributedContent))
        return textView
    }
    #endif
}

#if os(macOS)
@available(iOS 26.0, macOS 26.0, *)
private struct PlatformSelectableNoteReadView: NSViewRepresentable {
    let attributedContent: AttributedString
    let onActivateEditing: (() -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let textView = SelectableNoteReadView.makePlatformTextView(
            attributedContent: attributedContent,
            onActivateEditing: onActivateEditing
        )
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? SelectableNoteReadTextView else {
            return
        }
        textView.onActivateEditing = onActivateEditing
        let updatedContent = NSAttributedString(attributedContent)
        if textView.textStorage?.isEqual(to: updatedContent) == false {
            textView.textStorage?.setAttributedString(updatedContent)
        }
    }
}

@available(iOS 26.0, macOS 26.0, *)
private final class SelectableNoteReadTextView: NSTextView {
    var onActivateEditing: (() -> Void)?
    private var didDragSelectionGesture = false

    override func mouseDown(with event: NSEvent) {
        didDragSelectionGesture = false
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        didDragSelectionGesture = true
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        super.mouseUp(with: event)
        let shouldActivateEditing = shouldActivateEditing(
            clickCount: event.clickCount,
            point: point
        )
        guard shouldActivateEditing else { return }
        onActivateEditing?()
    }

    private func shouldActivateEditing(
        clickCount: Int,
        point: NSPoint
    ) -> Bool {
        guard clickCount == 1,
              didDragSelectionGesture == false,
              linkAttribute(at: point) == nil else {
            return false
        }
        return onActivateEditing != nil
    }

    private func linkAttribute(at point: NSPoint) -> Any? {
        guard let layoutManager,
              let textContainer,
              let textStorage,
              textStorage.length > 0 else {
            return nil
        }

        let containerPoint = NSPoint(
            x: point.x - textContainerInset.width,
            y: point.y - textContainerInset.height
        )
        let glyphIndex = layoutManager.glyphIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceThroughGlyph: nil
        )
        guard glyphIndex < layoutManager.numberOfGlyphs else {
            return nil
        }
        let glyphRange = NSRange(location: glyphIndex, length: 1)
        let glyphBounds = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        guard glyphBounds.insetBy(dx: -1, dy: -1).contains(containerPoint) else {
            return nil
        }
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard characterIndex < textStorage.length else { return nil }
        return textStorage.attribute(.link, at: characterIndex, effectiveRange: nil)
    }
}
#elseif os(iOS)
@available(iOS 26.0, macOS 26.0, *)
private struct PlatformSelectableNoteReadView: UIViewRepresentable {
    let attributedContent: AttributedString
    let onActivateEditing: (() -> Void)?

    func makeUIView(context: Context) -> UITextView {
        let textView = SelectableNoteReadTextView()
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = UIEdgeInsets(
            top: NoteTextLayout.verticalPadding,
            left: NoteTextLayout.horizontalPadding,
            bottom: NoteTextLayout.verticalPadding,
            right: NoteTextLayout.horizontalPadding
        )
        textView.textContainer.lineFragmentPadding = 0
        textView.linkTextAttributes = [
            .foregroundColor: UIColor.link,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        textView.onActivateEditing = onActivateEditing
        textView.attributedText = NSAttributedString(attributedContent)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        guard let readTextView = textView as? SelectableNoteReadTextView else { return }
        readTextView.onActivateEditing = onActivateEditing
        let updatedContent = NSAttributedString(attributedContent)
        if readTextView.attributedText.isEqual(to: updatedContent) == false {
            readTextView.attributedText = updatedContent
        }
    }
}

@available(iOS 26.0, macOS 26.0, *)
private final class SelectableNoteReadTextView: UITextView {
    var onActivateEditing: (() -> Void)?
    private var didDragSelectionGesture = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        didDragSelectionGesture = false
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        didDragSelectionGesture = true
        super.touchesMoved(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let touch = touches.first
        let point = touch?.location(in: self)
        let tapCount = touch?.tapCount ?? 0
        super.touchesEnded(touches, with: event)

        guard tapCount == 1,
              didDragSelectionGesture == false,
              let point,
              linkAttribute(at: point) == nil else {
            return
        }
        onActivateEditing?()
    }

    private func linkAttribute(at point: CGPoint) -> Any? {
        guard attributedText.length > 0 else { return nil }
        var containerPoint = point
        containerPoint.x -= textContainerInset.left
        containerPoint.y -= textContainerInset.top

        let characterIndex = layoutManager.characterIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        guard characterIndex < attributedText.length else { return nil }
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: characterIndex, length: 1),
            actualCharacterRange: nil
        )
        let glyphBounds = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        guard glyphBounds.insetBy(dx: -1, dy: -1).contains(containerPoint) else {
            return nil
        }
        return attributedText.attribute(.link, at: characterIndex, effectiveRange: nil)
    }
}
#endif
