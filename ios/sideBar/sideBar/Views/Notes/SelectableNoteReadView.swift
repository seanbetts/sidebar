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
    var onActivateEditingWithViewport: ((ReadActivationTarget, CGFloat?) -> Void)?
    var onViewportOffsetChange: ((CGPoint) -> Void)?
    var initialViewportOffset: CGPoint?
    var onInitialViewportOffsetApplied: (() -> Void)?
    var shouldRestoreFocusOnAppear: Bool
    @AppStorage(AppStorageKeys.appTextSize) private var appTextSizeRaw = AppTextSizeOption.system.rawValue

    init(
        document: NotesSemanticDocument,
        maxContentWidth: CGFloat,
        onActivateEditing: ((ReadActivationTarget) -> Void)? = nil,
        onActivateEditingWithViewport: ((ReadActivationTarget, CGFloat?) -> Void)? = nil,
        onViewportOffsetChange: ((CGPoint) -> Void)? = nil,
        initialViewportOffset: CGPoint? = nil,
        onInitialViewportOffsetApplied: (() -> Void)? = nil,
        shouldRestoreFocusOnAppear: Bool = false
    ) {
        self.document = document
        self.maxContentWidth = maxContentWidth
        self.onActivateEditing = onActivateEditing
        self.onActivateEditingWithViewport = onActivateEditingWithViewport
        self.onViewportOffsetChange = onViewportOffsetChange
        self.initialViewportOffset = initialViewportOffset
        self.onInitialViewportOffsetApplied = onInitialViewportOffsetApplied
        self.shouldRestoreFocusOnAppear = shouldRestoreFocusOnAppear
    }

    init(
        document: NotesSemanticDocument,
        maxContentWidth: CGFloat,
        onActivateEditing: (() -> Void)?
    ) {
        self.init(document: document, maxContentWidth: maxContentWidth, onActivateEditing: { _ in onActivateEditing?() })
    }

    var body: some View {
        let baseFontSize = Self.readBaseFontSize(for: resolvedTextSizeOption)
        PlatformSelectableNoteReadView(
            attributedContent: Self.makePlatformAttributedContent(
                from: document,
                baseFontSize: baseFontSize
            ),
            maxReadableContentWidth: maxContentWidth,
            onActivateEditing: onActivateEditing,
            onActivateEditingWithViewport: onActivateEditingWithViewport,
            onViewportOffsetChange: onViewportOffsetChange,
            initialViewportOffset: initialViewportOffset,
            onInitialViewportOffsetApplied: onInitialViewportOffsetApplied,
            shouldRestoreFocusOnAppear: shouldRestoreFocusOnAppear
        )
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
            let swiftTraits = noteSwiftUIFontTraits(
                from: noteExplicitSwiftUIFont(from: run.attributes)
            )
            let monospaced: Bool
            if let platformFont = noteExplicitPlatformFont(from: run.attributes) {
                monospaced = notePlatformFontTraits(from: platformFont).monospaced
            } else {
                monospaced = false
            }
            let hasExplicitBlock = run.noteBlock != nil
            if hasExplicitBlock {
                mutable.addAttribute(
                    .font,
                    value: notePlatformFont(
                        baseFontSize: baseFontSize,
                        blockType: blockType,
                        bold: swiftTraits.bold,
                        italic: swiftTraits.italic,
                        inlineCode: monospaced
                    ),
                    range: nsRange
                )
            } else {
                let pointSize = noteBlockPointSize(
                    baseFontSize: baseFontSize,
                    blockType: blockType
                )
                mutable.addAttribute(
                    .font,
                    value: notePlatformFont(
                        baseFontSize: pointSize,
                        bold: swiftTraits.bold,
                        italic: swiftTraits.italic,
                        monospaced: monospaced
                    ),
                    range: nsRange
                )
            }
            mutable.addAttribute(
                .paragraphStyle,
                value: run.paragraphStyle ?? paragraphStyle(for: blockType, baseFontSize: baseFontSize),
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
            if run.strikethroughStyle != nil {
                mutable.addAttribute(
                    .strikethroughStyle,
                    value: NSUnderlineStyle.single.rawValue,
                    range: nsRange
                )
            } else {
                mutable.removeAttribute(.strikethroughStyle, range: nsRange)
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
        noteSwiftUIFontTraits(from: noteExplicitSwiftUIFont(from: run.attributes))
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
        case .unorderedList, .checklist:
            return NoteTextParagraphMetrics.paragraphStyle(
                for: blockType,
                baseFontSize: baseFontSize,
                headIndent: baseFontSize
            )
        case .orderedList:
            let contentIndent = NoteTextParagraphMetrics.orderedListContentIndent(
                baseFontSize: baseFontSize
            )
            let markerIndent = NoteTextParagraphMetrics.orderedListMarkerIndent(
                baseFontSize: baseFontSize
            )
            return NoteTextParagraphMetrics.paragraphStyle(
                for: blockType,
                baseFontSize: baseFontSize,
                headIndent: contentIndent,
                firstLineHeadIndent: markerIndent,
                tabStops: [
                    NSTextTab(textAlignment: .left, location: contentIndent)
                ],
                defaultTabInterval: contentIndent
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
        onActivateEditing: ((ReadActivationTarget) -> Void)? = nil,
        onActivateEditingWithViewport: ((ReadActivationTarget, CGFloat?) -> Void)? = nil
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
        textView.onActivateEditingWithViewport = onActivateEditingWithViewport
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

    static func activateEditingForTesting(
        in textView: NSTextView,
        at point: NSPoint
    ) {
        guard let readTextView = textView as? SelectableNoteReadTextView else { return }
        readTextView.activateEditingForTesting(at: point)
    }
    #endif
}

#if os(macOS)
@available(iOS 26.0, macOS 26.0, *)
private final class SelectableNoteReadScrollView: NSScrollView {
    var onViewportOffsetChange: ((CGPoint) -> Void)?
    var pendingViewportOffset: CGPoint?
    var onPendingViewportOffsetApplied: (() -> Void)?
    var shouldRestoreFocusOnAppear = false
    private var lastReportedViewportOffset: CGPoint?

    override func layout() {
        super.layout()
        applyPendingViewportOffsetIfNeeded()
        restoreReadFocusIfNeeded()
        reportViewportOffsetIfNeeded(force: true)
    }

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        reportViewportOffsetIfNeeded()
    }

    private func applyPendingViewportOffsetIfNeeded() {
        guard let pendingViewportOffset else { return }
        if pendingViewportOffset.y > 0,
           (documentView?.frame.height ?? 0) <= contentView.bounds.height {
            return
        }
        let maxX = max((documentView?.frame.width ?? 0) - contentView.bounds.width, 0)
        let maxY = max((documentView?.frame.height ?? 0) - contentView.bounds.height, 0)
        let clampedOffset = CGPoint(
            x: min(max(pendingViewportOffset.x, 0), maxX),
            y: min(max(pendingViewportOffset.y, 0), maxY)
        )
        guard contentView.bounds.origin != clampedOffset else {
            self.pendingViewportOffset = nil
            onPendingViewportOffsetApplied?()
            return
        }
        contentView.scroll(to: clampedOffset)
        reflectScrolledClipView(contentView)
        self.pendingViewportOffset = nil
        onPendingViewportOffsetApplied?()
    }

    private func restoreReadFocusIfNeeded() {
        guard shouldRestoreFocusOnAppear,
              let textView = documentView as? NSTextView,
              window?.firstResponder !== textView else { return }
        shouldRestoreFocusOnAppear = false
        DispatchQueue.main.async { [weak self, weak textView] in
            guard let self, let textView else { return }
            self.window?.makeFirstResponder(textView)
        }
    }

    private func reportViewportOffsetIfNeeded(force: Bool = false) {
        let viewportOffset = contentView.bounds.origin
        guard force || lastReportedViewportOffset != viewportOffset else { return }
        lastReportedViewportOffset = viewportOffset
        onViewportOffsetChange?(viewportOffset)
    }
}

@available(iOS 26.0, macOS 26.0, *)
private struct PlatformSelectableNoteReadView: NSViewRepresentable {
    let attributedContent: NSAttributedString
    let maxReadableContentWidth: CGFloat
    let onActivateEditing: ((SelectableNoteReadView.ReadActivationTarget) -> Void)?
    let onActivateEditingWithViewport: ((SelectableNoteReadView.ReadActivationTarget, CGFloat?) -> Void)?
    let onViewportOffsetChange: ((CGPoint) -> Void)?
    let initialViewportOffset: CGPoint?
    let onInitialViewportOffsetApplied: (() -> Void)?
    let shouldRestoreFocusOnAppear: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let textView = SelectableNoteReadView.makePlatformTextView(
            attributedContent: attributedContent,
            onActivateEditing: onActivateEditing,
            onActivateEditingWithViewport: onActivateEditingWithViewport
        )
        guard let readTextView = textView as? SelectableNoteReadTextView else {
            preconditionFailure("Expected SelectableNoteReadTextView for macOS read surface")
        }
        readTextView.maxReadableContentWidth = maxReadableContentWidth
        let scrollView = SelectableNoteReadScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.onViewportOffsetChange = onViewportOffsetChange
        scrollView.pendingViewportOffset = initialViewportOffset
        scrollView.onPendingViewportOffsetApplied = onInitialViewportOffsetApplied
        scrollView.shouldRestoreFocusOnAppear = shouldRestoreFocusOnAppear
        scrollView.documentView = readTextView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? SelectableNoteReadTextView else {
            return
        }
        if let trackingScrollView = scrollView as? SelectableNoteReadScrollView {
            trackingScrollView.onViewportOffsetChange = onViewportOffsetChange
            if trackingScrollView.pendingViewportOffset == nil {
                trackingScrollView.pendingViewportOffset = initialViewportOffset
            }
            trackingScrollView.onPendingViewportOffsetApplied = onInitialViewportOffsetApplied
            trackingScrollView.shouldRestoreFocusOnAppear = shouldRestoreFocusOnAppear
        }
        textView.maxReadableContentWidth = maxReadableContentWidth
        textView.onActivateEditing = onActivateEditing
        textView.onActivateEditingWithViewport = onActivateEditingWithViewport
        if textView.textStorage?.isEqual(to: attributedContent) == false {
            textView.textStorage?.setAttributedString(attributedContent)
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: ()) {
        if let trackingScrollView = scrollView as? SelectableNoteReadScrollView {
            trackingScrollView.onViewportOffsetChange = nil
            trackingScrollView.onPendingViewportOffsetApplied = nil
            trackingScrollView.pendingViewportOffset = nil
            trackingScrollView.shouldRestoreFocusOnAppear = false
        }
        guard let textView = scrollView.documentView as? SelectableNoteReadTextView else {
            return
        }
        textView.onActivateEditing = nil
        textView.onActivateEditingWithViewport = nil
        scrollView.documentView = nil
    }
}

@available(iOS 26.0, macOS 26.0, *)
private final class SelectableNoteReadTextView: NSTextView {
    private static let baseTextContainerInset = NSSize(
        width: NoteTextLayout.horizontalPadding,
        height: NoteTextLayout.verticalPadding
    )

    var onActivateEditing: ((SelectableNoteReadView.ReadActivationTarget) -> Void)?
    var onActivateEditingWithViewport: ((SelectableNoteReadView.ReadActivationTarget, CGFloat?) -> Void)?
    var maxReadableContentWidth: CGFloat = .greatestFiniteMagnitude {
        didSet { needsLayout = true }
    }
    private var didDragSelectionGesture = false
    private var lastActivationTimestamp: TimeInterval = 0

    override func layout() {
        super.layout()
        updateTextContainerInset()
    }

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

    private func activateEditingIfNeeded(at point: NSPoint) {
        guard let target = activationTarget(at: point), canTriggerActivationNow else { return }
        lastActivationTimestamp = ProcessInfo.processInfo.systemUptime
        if let onActivateEditingWithViewport {
            onActivateEditingWithViewport(target, activationViewportAnchorY(for: target))
        } else {
            onActivateEditing?(target)
        }
    }

    fileprivate func activateEditingForTesting(at point: NSPoint) {
        activateEditingIfNeeded(at: point)
    }

    private var canTriggerActivationNow: Bool {
        let now = ProcessInfo.processInfo.systemUptime
        return now - lastActivationTimestamp > 0.2
    }

    private func updateTextContainerInset() {
        let extraHorizontalInset = max((bounds.width - maxReadableContentWidth) / 2, 0)
        let resolvedInset = NSSize(
            width: Self.baseTextContainerInset.width + extraHorizontalInset,
            height: Self.baseTextContainerInset.height
        )
        guard textContainerInset != resolvedInset else { return }
        textContainerInset = resolvedInset
    }

    private func activationViewportAnchorY(
        for target: SelectableNoteReadView.ReadActivationTarget
    ) -> CGFloat? {
        let characterOffset: Int
        switch target {
        case .start:
            characterOffset = 0
        case .characterOffset(let offset):
            characterOffset = offset
        }
        guard let selectionMidY = selectionMidY(forCharacterOffset: characterOffset),
              let scrollView = enclosingScrollView else {
            return nil
        }
        return selectionMidY - scrollView.contentView.bounds.minY
    }

    private func selectionMidY(forCharacterOffset characterOffset: Int) -> CGFloat? {
        guard let layoutManager,
              let textContainer else {
            return nil
        }
        textContainer.containerSize = NSSize(
            width: max(bounds.width, 0),
            height: CGFloat.greatestFiniteMagnitude
        )
        layoutManager.ensureLayout(for: textContainer)
        guard layoutManager.numberOfGlyphs > 0 else {
            return textContainerInset.height
        }
        let clampedCharacterOffset = min(max(characterOffset, 0), string.utf16.count)
        let glyphIndex: Int
        if clampedCharacterOffset >= string.utf16.count {
            glyphIndex = max(layoutManager.numberOfGlyphs - 1, 0)
        } else {
            glyphIndex = layoutManager.glyphIndexForCharacter(at: clampedCharacterOffset)
        }
        let lineRect = layoutManager.lineFragmentUsedRect(
            forGlyphAt: glyphIndex,
            effectiveRange: nil
        )
        return textContainerInset.height + lineRect.midY
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
    let maxReadableContentWidth: CGFloat
    let onActivateEditing: ((SelectableNoteReadView.ReadActivationTarget) -> Void)?
    let onActivateEditingWithViewport: ((SelectableNoteReadView.ReadActivationTarget, CGFloat?) -> Void)?
    let onViewportOffsetChange: ((CGPoint) -> Void)?

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
        textView.maxReadableContentWidth = maxReadableContentWidth
        textView.linkTextAttributes = [
            .foregroundColor: UIColor.link,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        textView.onActivateEditing = onActivateEditing
        textView.onActivateEditingWithViewport = onActivateEditingWithViewport
        textView.onViewportOffsetChange = onViewportOffsetChange
        textView.attributedText = attributedContent
        containerView.onActivateEditing = onActivateEditing
        containerView.onActivateEditingWithViewport = onActivateEditingWithViewport
        return containerView
    }

    func updateUIView(_ containerView: SelectableNoteReadContainerView, context: Context) {
        let readTextView = containerView.textView
        readTextView.maxReadableContentWidth = maxReadableContentWidth
        readTextView.onActivateEditing = onActivateEditing
        readTextView.onActivateEditingWithViewport = onActivateEditingWithViewport
        readTextView.onViewportOffsetChange = onViewportOffsetChange
        containerView.onActivateEditing = onActivateEditing
        containerView.onActivateEditingWithViewport = onActivateEditingWithViewport
        if readTextView.attributedText.isEqual(to: attributedContent) == false {
            readTextView.attributedText = attributedContent
        }
    }
}

@available(iOS 26.0, macOS 26.0, *)
private final class SelectableNoteReadTextView: UITextView {
    private static let baseTextContainerInsets = UIEdgeInsets(
        top: NoteTextLayout.verticalPadding,
        left: NoteTextLayout.horizontalPadding,
        bottom: NoteTextLayout.verticalPadding,
        right: NoteTextLayout.horizontalPadding
    )

    var onActivateEditing: ((SelectableNoteReadView.ReadActivationTarget) -> Void)?
    var onActivateEditingWithViewport: ((SelectableNoteReadView.ReadActivationTarget, CGFloat?) -> Void)?
    var onViewportOffsetChange: ((CGPoint) -> Void)? {
        didSet { reportViewportOffsetIfNeeded(force: true) }
    }
    var maxReadableContentWidth: CGFloat = .greatestFiniteMagnitude {
        didSet { setNeedsLayout() }
    }
    private var lastReportedViewportOffset: CGPoint?

    override var contentOffset: CGPoint {
        didSet {
            reportViewportOffsetIfNeeded()
        }
    }

    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        super.setContentOffset(contentOffset, animated: animated)
        reportViewportOffsetIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateTextContainerInsets()
        reportViewportOffsetIfNeeded()
    }

    private func updateTextContainerInsets() {
        let extraHorizontalInset = max((bounds.width - maxReadableContentWidth) / 2, 0)
        let resolvedInsets = UIEdgeInsets(
            top: Self.baseTextContainerInsets.top,
            left: Self.baseTextContainerInsets.left + extraHorizontalInset,
            bottom: Self.baseTextContainerInsets.bottom,
            right: Self.baseTextContainerInsets.right + extraHorizontalInset
        )
        guard textContainerInset != resolvedInsets else { return }
        textContainerInset = resolvedInsets
    }

    private func reportViewportOffsetIfNeeded(force: Bool = false) {
        guard force || lastReportedViewportOffset != contentOffset else { return }
        lastReportedViewportOffset = contentOffset
        onViewportOffsetChange?(contentOffset)
    }

    private func linkAttribute(at point: CGPoint) -> Any? {
        guard attributedText.length > 0 else { return nil }
        let layoutManager = self.layoutManager
        let textContainer = self.textContainer

        let containerPoint = CGPoint(
            x: point.x - textContainerInset.left,
            y: point.y - textContainerInset.top
        )
        layoutManager.ensureLayout(for: textContainer)
        let glyphIndex = layoutManager.glyphIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceThroughGlyph: nil
        )
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }

        let glyphRange = NSRange(location: glyphIndex, length: 1)
        let glyphBounds = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        guard glyphBounds.insetBy(dx: -1, dy: -1).contains(containerPoint) else {
            return nil
        }

        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard characterIndex < attributedText.length else { return nil }
        return attributedText.attribute(.link, at: characterIndex, effectiveRange: nil)
    }

    func activationTarget(at point: CGPoint) -> SelectableNoteReadView.ReadActivationTarget? {
        guard linkAttribute(at: point) == nil,
              let characterOffset = SelectableNoteReadView.characterOffsetForEditingActivation(in: self, at: point) else { return nil }
        return .characterOffset(characterOffset)
    }

    func activationViewportAnchorY(
        for target: SelectableNoteReadView.ReadActivationTarget
    ) -> CGFloat? {
        let characterOffset: Int
        switch target {
        case .start:
            characterOffset = 0
        case .characterOffset(let offset):
            characterOffset = offset
        }
        guard let position = position(
            from: beginningOfDocument,
            offset: min(max(characterOffset, 0), attributedText.length)
        ) else {
            return nil
        }
        let viewport = bounds.inset(by: adjustedContentInset)
        guard viewport.height > 0 else { return nil }
        let caretRect = caretRect(for: position)
        return caretRect.midY - viewport.minY
    }
}

@available(iOS 26.0, macOS 26.0, *)
private final class SelectableNoteReadContainerView: UIView, UIGestureRecognizerDelegate {
    let textView = SelectableNoteReadTextView()
    var onActivateEditing: ((SelectableNoteReadView.ReadActivationTarget) -> Void)?
    var onActivateEditingWithViewport: ((SelectableNoteReadView.ReadActivationTarget, CGFloat?) -> Void)?

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
        if let onActivateEditingWithViewport {
            onActivateEditingWithViewport(target, textView.activationViewportAnchorY(for: target))
        } else {
            onActivateEditing?(target)
        }
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
