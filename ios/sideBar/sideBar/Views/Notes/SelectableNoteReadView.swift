import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
// swiftlint:disable file_length

@available(iOS 26.0, macOS 26.0, *)
struct SelectableNoteReadView: View {
    typealias ReadActivationTarget = NotesEditorViewModel.PendingEditSelectionTarget

    let document: NotesSemanticDocument
    let maxContentWidth: CGFloat
    var onActivateEditing: ((ReadActivationTarget) -> Void)?
    @AppStorage(AppStorageKeys.appTextSize) private var appTextSizeRaw = AppTextSizeOption.system.rawValue

    init(
        document: NotesSemanticDocument,
        maxContentWidth: CGFloat,
        onActivateEditing: ((ReadActivationTarget) -> Void)? = nil
    ) {
        self.document = document
        self.maxContentWidth = maxContentWidth
        self.onActivateEditing = onActivateEditing
    }

    init(
        document: NotesSemanticDocument,
        maxContentWidth: CGFloat,
        onActivateEditing: (() -> Void)?
    ) {
        self.init(document: document, maxContentWidth: maxContentWidth) { _ in onActivateEditing?() }
    }

    var body: some View {
        let baseFontSize = Self.readBaseFontSize(for: resolvedTextSizeOption)
        PlatformSelectableNoteReadView(
            attributedContent: Self.makePlatformAttributedContent(
                from: document,
                baseFontSize: baseFontSize
            ),
            onActivateEditing: onActivateEditing
        )
        .padding(.horizontal, NoteTextLayout.horizontalPadding)
        .padding(.vertical, NoteTextLayout.verticalPadding)
        .frame(maxWidth: maxContentWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.background)
    }

    private var resolvedTextSizeOption: AppTextSizeOption { AppTextSizeOption.resolved(from: appTextSizeRaw) }

    static func makeAttributedContent(
        from document: NotesSemanticDocument,
        baseFontSize: CGFloat = NoteTextTypography.defaultBodyFontSize
    ) -> AttributedString {
        NotesAttributedDocumentCodec.readAttributedString(
            from: document,
            baseFontSize: baseFontSize
        )
    }

    static func readBaseFontSize(for option: AppTextSizeOption) -> CGFloat { NoteTextTypography.defaultBodyFontSize(for: option) }

    static func makePlatformAttributedContent(
        from document: NotesSemanticDocument,
        baseFontSize: CGFloat = NoteTextTypography.defaultBodyFontSize
    ) -> NSAttributedString {
        bridgedPlatformAttributedString(
            from: makeAttributedContent(from: document, baseFontSize: baseFontSize),
            baseFontSize: baseFontSize
        )
    }

    static func bridgedPlatformAttributedString(
        from attributed: AttributedString,
        baseFontSize: CGFloat
    ) -> NSAttributedString {
        let base = (try? NSAttributedString(attributed, including: \.noteTextEditor))
            ?? NSAttributedString(attributed)
        guard base.length > 0 else { return base }

        let mutable = NSMutableAttributedString(attributedString: base)
        let plainText = String(attributed.characters)

        for run in attributed.runs {
            let nsRange = nsRange(for: run.range, in: attributed, plainText: plainText)
            guard nsRange.length > 0 else { continue }

            let blockType = blockType(for: run, in: attributed)
            let traits = noteInlineTraits(for: run)
            mutable.addAttribute(
                .font,
                value: notePlatformFont(
                    baseFontSize: baseFontSize,
                    blockType: blockType,
                    bold: traits.bold,
                    italic: traits.italic,
                    inlineCode: traits.monospaced
                ),
                range: nsRange
            )
            mutable.addAttribute(
                .paragraphStyle,
                value: paragraphStyle(for: blockType, baseFontSize: baseFontSize),
                range: nsRange
            )
            if run.underlineStyle != nil {
                mutable.addAttribute(
                    .underlineStyle,
                    value: NSUnderlineStyle.single.rawValue,
                    range: nsRange
                )
            } else {
                mutable.removeAttribute(.underlineStyle, range: nsRange)
            }
        }

        mutable.addAttribute(
            .foregroundColor,
            value: defaultPlatformTextColor,
            range: NSRange(location: 0, length: mutable.length)
        )
        return mutable
    }

    #if os(iOS)
    private static var defaultPlatformTextColor: UIColor { .label }
    #elseif os(macOS)
    private static var defaultPlatformTextColor: NSColor { .labelColor }
    #endif

    private static func nsRange(
        for range: Range<AttributedString.Index>,
        in content: AttributedString,
        plainText: String
    ) -> NSRange {
        let lowerCharacterOffset = content.characters.distance(
            from: content.startIndex,
            to: range.lowerBound
        )
        let upperCharacterOffset = content.characters.distance(
            from: content.startIndex,
            to: range.upperBound
        )
        let lower = plainText.index(plainText.startIndex, offsetBy: lowerCharacterOffset)
        let upper = plainText.index(plainText.startIndex, offsetBy: upperCharacterOffset)
        return NSRange(
            location: lower.utf16Offset(in: plainText),
            length: upper.utf16Offset(in: plainText) - lower.utf16Offset(in: plainText)
        )
    }

    private static func noteInlineTraits(
        for run: AttributedString.Runs.Run
    ) -> NoteInlineFormattingTraits {
        noteInlineFormattingTraits(from: run.attributes)
    }

    private static func blockType(
        for run: AttributedString.Runs.Run,
        in attributed: AttributedString
    ) -> NotesSemanticDocument.BlockType {
        NoteTextBlockResolution.resolvedBlockType(for: run, in: attributed)
    }

    private static func paragraphStyle(
        for blockType: NotesSemanticDocument.BlockType,
        baseFontSize: CGFloat
    ) -> NSParagraphStyle {
        switch blockType {
        case .unorderedList, .orderedList, .checklist:
            return NoteTextParagraphMetrics.paragraphStyle(
                for: blockType,
                baseFontSize: baseFontSize,
                headIndent: baseFontSize
            )
        case .blockquote:
            return NoteTextParagraphMetrics.paragraphStyle(
                for: blockType,
                baseFontSize: baseFontSize,
                headIndent: baseFontSize * 1.25
            )
        case .codeBlock:
            return NoteTextParagraphMetrics.paragraphStyle(
                for: blockType,
                baseFontSize: baseFontSize,
                headIndent: baseFontSize * 0.75,
                tailIndent: baseFontSize * 0.75
            )
        default:
            return NoteTextParagraphMetrics.paragraphStyle(for: blockType, baseFontSize: baseFontSize)
        }
    }

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

    #if os(macOS)
    static func makePlatformTextView(
        attributedContent: NSAttributedString,
        onActivateEditing: ((ReadActivationTarget) -> Void)? = nil
    ) -> NSTextView {
        let textView = SelectableNoteReadTextView()
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.textContainer?.widthTracksTextView = true
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
        textView.onActivateEditing = onActivateEditing
        textView.installActivationClickRecognizerIfNeeded()
        textView.textStorage?.setAttributedString(attributedContent)
        return textView
    }

    static func characterOffsetForEditingActivation(
        in textView: NSTextView,
        at point: NSPoint
    ) -> Int? {
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return nil }
        textContainer.containerSize = NSSize(width: max(textView.bounds.width, 0), height: CGFloat.greatestFiniteMagnitude)
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

        let insertionIndex = textView.characterIndexForInsertion(at: point)
        return min(max(insertionIndex, 0), plainText.length)
    }
    #endif
}

#if os(macOS)
@available(iOS 26.0, macOS 26.0, *)
private struct PlatformSelectableNoteReadView: NSViewRepresentable {
    let attributedContent: NSAttributedString
    let onActivateEditing: ((SelectableNoteReadView.ReadActivationTarget) -> Void)?

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
        if textView.textStorage?.isEqual(to: attributedContent) == false {
            textView.textStorage?.setAttributedString(attributedContent)
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: ()) {
        guard let textView = scrollView.documentView as? SelectableNoteReadTextView else {
            return
        }
        textView.onActivateEditing = nil
        scrollView.documentView = nil
    }
}

@available(iOS 26.0, macOS 26.0, *)
private final class SelectableNoteReadTextView: NSTextView {
    var onActivateEditing: ((SelectableNoteReadView.ReadActivationTarget) -> Void)?
    private var didDragSelectionGesture = false
    private var lastActivationTimestamp: TimeInterval = 0

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
        guard event.clickCount == 1, didDragSelectionGesture == false else { return }
        activateEditingIfNeeded(at: point)
    }

    func installActivationClickRecognizerIfNeeded() {
        let hasRecognizer = gestureRecognizers.contains { recognizer in
            guard let clickRecognizer = recognizer as? NSClickGestureRecognizer else {
                return false
            }
            return clickRecognizer.numberOfClicksRequired == 1
        }
        guard hasRecognizer == false else { return }

        let clickRecognizer = NSClickGestureRecognizer(
            target: self,
            action: #selector(handleActivationClickGesture(_:))
        )
        clickRecognizer.numberOfClicksRequired = 1
        addGestureRecognizer(clickRecognizer)
    }

    @objc
    private func handleActivationClickGesture(_ recognizer: NSClickGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        activateEditingIfNeeded(at: recognizer.location(in: self))
    }

    private func activateEditingIfNeeded(at point: NSPoint) {
        guard let onActivateEditing, let target = activationTarget(at: point), canTriggerActivationNow else { return }
        lastActivationTimestamp = ProcessInfo.processInfo.systemUptime
        onActivateEditing(target)
    }

    private var canTriggerActivationNow: Bool {
        let now = ProcessInfo.processInfo.systemUptime
        return now - lastActivationTimestamp > 0.2
    }

    private func linkAttribute(at point: NSPoint) -> Any? {
        guard let layoutManager, let textContainer, let textStorage, textStorage.length > 0 else { return nil }
        let containerPoint = NSPoint(
            x: point.x - textContainerInset.width,
            y: point.y - textContainerInset.height
        )
        let glyphIndex = layoutManager.glyphIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceThroughGlyph: nil
        )
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }
        let glyphRange = NSRange(location: glyphIndex, length: 1)
        let glyphBounds = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        guard glyphBounds.insetBy(dx: -1, dy: -1).contains(containerPoint) else { return nil }
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard characterIndex < textStorage.length else { return nil }
        return textStorage.attribute(.link, at: characterIndex, effectiveRange: nil)
    }

    private func activationTarget(at point: NSPoint) -> SelectableNoteReadView.ReadActivationTarget? {
        guard linkAttribute(at: point) == nil,
              let characterOffset = SelectableNoteReadView.characterOffsetForEditingActivation(in: self, at: point) else { return nil }
        return .characterOffset(characterOffset)
    }
}
#elseif os(iOS)
@available(iOS 26.0, macOS 26.0, *)
private struct PlatformSelectableNoteReadView: UIViewRepresentable {
    let attributedContent: NSAttributedString
    let onActivateEditing: ((SelectableNoteReadView.ReadActivationTarget) -> Void)?

    func makeUIView(context: Context) -> SelectableNoteReadContainerView {
        let containerView = SelectableNoteReadContainerView()
        let textView = containerView.textView
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.adjustsFontForContentSizeCategory = false
        textView.textColor = .label
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainerInset = .zero
        textView.linkTextAttributes = [
            .foregroundColor: UIColor.link,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        textView.onActivateEditing = onActivateEditing
        textView.attributedText = attributedContent
        containerView.onActivateEditing = onActivateEditing
        return containerView
    }

    func updateUIView(_ containerView: SelectableNoteReadContainerView, context: Context) {
        let readTextView = containerView.textView
        readTextView.onActivateEditing = onActivateEditing
        containerView.onActivateEditing = onActivateEditing
        if readTextView.attributedText.isEqual(to: attributedContent) == false {
            readTextView.attributedText = attributedContent
        }
    }
}

@available(iOS 26.0, macOS 26.0, *)
private final class SelectableNoteReadTextView: UITextView {
    var onActivateEditing: ((SelectableNoteReadView.ReadActivationTarget) -> Void)?

    private func linkAttribute(at point: CGPoint) -> Any? {
        guard attributedText.length > 0 else { return nil }
        guard let closestPosition = closestPosition(to: point) else { return nil }
        let characterIndex = min(
            max(offset(from: beginningOfDocument, to: closestPosition), 0),
            attributedText.length
        )
        guard characterIndex < attributedText.length,
              let start = position(from: beginningOfDocument, offset: characterIndex),
              let end = position(from: start, offset: 1),
              let range = textRange(from: start, to: end) else {
            return nil
        }
        let characterRect = firstRect(for: range)
        guard characterRect.insetBy(dx: -1, dy: -1).contains(point) else {
            return nil
        }
        return attributedText.attribute(.link, at: characterIndex, effectiveRange: nil)
    }

    func activationTarget(at point: CGPoint) -> SelectableNoteReadView.ReadActivationTarget? {
        guard linkAttribute(at: point) == nil,
              let characterOffset = SelectableNoteReadView.characterOffsetForEditingActivation(in: self, at: point) else { return nil }
        return .characterOffset(characterOffset)
    }
}

@available(iOS 26.0, macOS 26.0, *)
private final class SelectableNoteReadContainerView: UIView, UIGestureRecognizerDelegate {
    let textView = SelectableNoteReadTextView()
    var onActivateEditing: ((SelectableNoteReadView.ReadActivationTarget) -> Void)?

    private lazy var activationTapRecognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(
            target: self,
            action: #selector(handleActivationTapGesture(_:))
        )
        recognizer.numberOfTapsRequired = 1
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        return recognizer
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        addGestureRecognizer(activationTapRecognizer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    private func handleActivationTapGesture(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        let point = recognizer.location(in: textView)
        guard let target = textView.activationTarget(at: point) else { return }
        onActivateEditing?(target)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        _ = gestureRecognizer
        _ = otherGestureRecognizer
        return true
    }
}

@available(iOS 26.0, macOS 26.0, *)
extension SelectableNoteReadView {
    static func characterOffsetForEditingActivation(
        in textView: UITextView,
        at point: CGPoint
    ) -> Int? {
        let plainTextLength = textView.attributedText.length
        guard plainTextLength > 0 else { return 0 }
        let endRect = textView.caretRect(for: textView.endOfDocument)
        if point.y > endRect.maxY { return plainTextLength }

        guard let position = textView.closestPosition(to: point) else { return plainTextLength }

        let offset = min(
            max(textView.offset(from: textView.beginningOfDocument, to: position), 0),
            plainTextLength
        )
        let visualLineEndOffset = visualLineEndOffset(
            from: position,
            in: textView,
            plainTextLength: plainTextLength
        )

        if let visualLineEndPosition = textView.position(
            from: textView.beginningOfDocument,
            offset: visualLineEndOffset
        ) {
            let lineEndRect = textView.caretRect(for: visualLineEndPosition)
            if point.x > lineEndRect.maxX {
                return visualLineEndOffset
            }
        }

        return offset
    }

    static func visualLineEndOffset(
        from position: UITextPosition,
        in textView: UITextView,
        plainTextLength: Int
    ) -> Int {
        var currentPosition = position
        var currentRect = textView.caretRect(for: position)
        var currentOffset = min(
            max(textView.offset(from: textView.beginningOfDocument, to: position), 0),
            plainTextLength
        )

        while currentOffset < plainTextLength,
              let nextPosition = textView.position(from: currentPosition, offset: 1) {
            let nextOffset = min(
                max(textView.offset(from: textView.beginningOfDocument, to: nextPosition), 0),
                plainTextLength
            )
            let nextRect = textView.caretRect(for: nextPosition)
            guard abs(nextRect.midY - currentRect.midY) <= 0.5 else { break }
            currentPosition = nextPosition
            currentRect = nextRect
            currentOffset = nextOffset
        }

        return currentOffset
    }
}
#endif
