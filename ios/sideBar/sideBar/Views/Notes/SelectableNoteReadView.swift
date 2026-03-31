import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
// swiftlint:disable file_length

final class ChecklistMarkerTextAttachment: NSTextAttachment {
    let isChecked: Bool

    init(isChecked: Bool) {
        self.isChecked = isChecked
        super.init(data: nil, ofType: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@available(iOS 26.0, macOS 26.0, *)
// swiftlint:disable type_body_length
struct SelectableNoteReadView: View {
    typealias ReadActivationTarget = NotesEditorViewModel.PendingEditSelectionTarget
    typealias ChecklistToggleHandler = (Int, Int) -> Void

    let document: NotesSemanticDocument
    let maxContentWidth: CGFloat
    var initialViewportOffset: CGPoint?
    var initialViewportAnchorTarget: ReadActivationTarget?
    var initialViewportAnchorY: CGFloat?
    var onActivateEditing: ((ReadActivationTarget) -> Void)?
    var onActivateEditingWithViewport: ((ReadActivationTarget, CGFloat?) -> Void)?
    var onToggleChecklistItem: ChecklistToggleHandler?
    var onViewportOffsetChange: ((CGPoint) -> Void)?
    var onInitialViewportRestorationApplied: (() -> Void)?
    @AppStorage(AppStorageKeys.appTextSize) private var appTextSizeRaw = AppTextSizeOption.system.rawValue

    init(
        document: NotesSemanticDocument,
        maxContentWidth: CGFloat,
        initialViewportOffset: CGPoint? = nil,
        initialViewportAnchorTarget: ReadActivationTarget? = nil,
        initialViewportAnchorY: CGFloat? = nil,
        onActivateEditing: ((ReadActivationTarget) -> Void)? = nil,
        onActivateEditingWithViewport: ((ReadActivationTarget, CGFloat?) -> Void)? = nil,
        onToggleChecklistItem: ChecklistToggleHandler? = nil,
        onViewportOffsetChange: ((CGPoint) -> Void)? = nil,
        onInitialViewportRestorationApplied: (() -> Void)? = nil
    ) {
        self.document = document
        self.maxContentWidth = maxContentWidth
        self.initialViewportOffset = initialViewportOffset
        self.initialViewportAnchorTarget = initialViewportAnchorTarget
        self.initialViewportAnchorY = initialViewportAnchorY
        self.onActivateEditing = onActivateEditing
        self.onActivateEditingWithViewport = onActivateEditingWithViewport
        self.onToggleChecklistItem = onToggleChecklistItem
        self.onViewportOffsetChange = onViewportOffsetChange
        self.onInitialViewportRestorationApplied = onInitialViewportRestorationApplied
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
            document: document,
            maxReadableContentWidth: maxContentWidth,
            initialViewportOffset: initialViewportOffset,
            initialViewportAnchorTarget: initialViewportAnchorTarget,
            initialViewportAnchorY: initialViewportAnchorY,
            onActivateEditing: onActivateEditing,
            onActivateEditingWithViewport: onActivateEditingWithViewport,
            onToggleChecklistItem: onToggleChecklistItem,
            onViewportOffsetChange: onViewportOffsetChange,
            onInitialViewportRestorationApplied: onInitialViewportRestorationApplied
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.background)
    }

    private var resolvedTextSizeOption: AppTextSizeOption { AppTextSizeOption.resolved(from: appTextSizeRaw) }

    static func makeAttributedContent(
        from document: NotesSemanticDocument,
        baseFontSize: CGFloat = NoteTextTypography.defaultBodyFontSize
    ) -> AttributedString {
        var attributed = NotesAttributedDocumentCodec.readAttributedString(
            from: document,
            baseFontSize: baseFontSize
        )
        NoteTextFormattingDefinition(baseFontSize: baseFontSize).constrainDocument(&attributed)
        return attributed
    }

    static func readBaseFontSize(for option: AppTextSizeOption) -> CGFloat { NoteTextTypography.defaultBodyFontSize(for: option) }

    static func makePlatformAttributedContent(
        from document: NotesSemanticDocument,
        baseFontSize: CGFloat = NoteTextTypography.defaultBodyFontSize
    ) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: bridgedPlatformAttributedString(
            from: makeAttributedContent(from: document, baseFontSize: baseFontSize),
            baseFontSize: baseFontSize
        ))
        replaceChecklistMarkersWithAttachments(
            in: mutable,
            document: document,
            baseFontSize: baseFontSize
        )
        return mutable
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
        mutable.addAttribute(
            .foregroundColor,
            value: defaultPlatformTextColor,
            range: NSRange(location: 0, length: mutable.length)
        )

        for run in attributed.runs {
            let nsRange = nsRange(for: run.range, in: attributed, plainText: plainText)
            guard nsRange.length > 0 else { continue }
            applyBridgedRunAttributes(
                for: run,
                nsRange: nsRange,
                in: attributed,
                mutable: mutable,
                baseFontSize: baseFontSize
            )
        }
        return mutable
    }

    #if os(iOS)
    private static var defaultPlatformTextColor: UIColor { .label }
    private static var checklistCompletedPlatformTextColor: UIColor {
        NoteTextAppearance.checklistCompletedTextColor
    }
    #elseif os(macOS)
    private static var defaultPlatformTextColor: NSColor { .labelColor }
    private static var checklistCompletedPlatformTextColor: NSColor {
        NoteTextAppearance.checklistCompletedTextColor
    }
    #endif

    private struct ChecklistMarkerReplacement {
        let range: NSRange
        let isChecked: Bool
    }

    static func replaceChecklistMarkersWithAttachments(
        in mutable: NSMutableAttributedString,
        document: NotesSemanticDocument,
        baseFontSize: CGFloat
    ) {
        let replacements = checklistMarkerReplacements(in: document)
        guard replacements.isEmpty == false else { return }

        for replacement in replacements.reversed() {
            let replacementString = checklistMarkerAttachmentString(
                from: mutable,
                range: replacement.range,
                isChecked: replacement.isChecked,
                baseFontSize: baseFontSize
            )
            mutable.replaceCharacters(in: replacement.range, with: replacementString)
        }
    }

    private static func checklistMarkerReplacements(
        in document: NotesSemanticDocument
    ) -> [ChecklistMarkerReplacement] {
        var replacements: [ChecklistMarkerReplacement] = []
        var offset = 0

        for (blockIndex, block) in document.blocks.enumerated() {
            if blockIndex > 0 {
                offset += 1
            }

            if block.type == .checklist {
                let children = block.children ?? []
                for (itemIndex, child) in children.enumerated() {
                    if itemIndex > 0 {
                        offset += 1
                    }
                    replacements.append(
                        ChecklistMarkerReplacement(
                            range: NSRange(location: offset, length: 6),
                            isChecked: child.checked == true
                        )
                    )
                    offset += 6 + utf16Length(for: child.content)
                }
                continue
            }

            offset += utf16Length(
                of: NotesSemanticDocumentProjection.plainText(
                    from: NotesSemanticDocument(
                        version: NotesSemanticDocument.currentVersion,
                        blocks: [block]
                    )
                )
            )
        }

        return replacements
    }

    private static func checklistMarkerAttachmentString(
        from mutable: NSMutableAttributedString,
        range: NSRange,
        isChecked: Bool,
        baseFontSize: CGFloat
    ) -> NSAttributedString {
        let font = (range.location < mutable.length
            ? mutable.attribute(.font, at: range.location, effectiveRange: nil) as? NotePlatformFont
            : nil)
        let paragraphStyle = (range.location < mutable.length
            ? mutable.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
            : nil)
        let markerColor = isChecked ? checklistCompletedPlatformTextColor : defaultPlatformTextColor

        let attachment = ChecklistMarkerTextAttachment(isChecked: isChecked)
        attachment.image = checklistMarkerImage(
            isChecked: isChecked,
            pointSize: font?.pointSize ?? baseFontSize,
            color: markerColor
        )
        attachment.bounds = checklistMarkerAttachmentBounds(
            for: attachment.image?.size ?? .zero,
            capHeight: font.map(notePlatformCapHeight) ?? (font?.pointSize ?? baseFontSize) * 0.7
        )

        let marker = NSMutableAttributedString(
            attributedString: NSAttributedString(attachment: attachment)
        )
        var markerAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: markerColor,
            NSAttributedString.Key(NoteTextChecklistCompletionAttribute.name): NSNumber(value: isChecked)
        ]
        if let font {
            markerAttributes[.font] = font
        }
        if let paragraphStyle {
            markerAttributes[.paragraphStyle] = paragraphStyle
        }
        marker.addAttributes(
            markerAttributes,
            range: NSRange(location: 0, length: marker.length)
        )
        marker.append(
            NSAttributedString(
                string: " ",
                attributes: markerAttributes
            )
        )
        return marker
    }

    #if os(iOS)
    private static func checklistMarkerImage(
        isChecked: Bool,
        pointSize: CGFloat,
        color: UIColor
    ) -> UIImage {
        let configuration = UIImage.SymbolConfiguration(
            pointSize: pointSize * 0.95,
            weight: .regular
        )
        return UIImage(
            systemName: isChecked ? "checkmark.square.fill" : "square",
            withConfiguration: configuration
        )?.withTintColor(color, renderingMode: .alwaysOriginal) ?? UIImage()
    }
    #elseif os(macOS)
    private static func checklistMarkerImage(
        isChecked: Bool,
        pointSize: CGFloat,
        color: NSColor
    ) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(
            pointSize: pointSize * 0.95,
            weight: .regular
        )
        guard let symbol = NSImage(
            systemSymbolName: isChecked ? "checkmark.square.fill" : "square",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(configuration) else {
            return NSImage()
        }
        return tintedChecklistMarkerImage(symbol, color: color)
    }

    private static func tintedChecklistMarkerImage(
        _ image: NSImage,
        color: NSColor
    ) -> NSImage {
        let tinted = NSImage(size: image.size)
        tinted.lockFocus()
        let rect = NSRect(origin: .zero, size: image.size)
        image.draw(in: rect)
        color.set()
        rect.fill(using: .sourceAtop)
        tinted.unlockFocus()
        tinted.isTemplate = false
        return tinted
    }
    #endif

    private static func checklistMarkerAttachmentBounds(
        for imageSize: CGSize,
        capHeight: CGFloat
    ) -> CGRect {
        let verticalOffset = floor((capHeight - imageSize.height) * 0.5)
        return CGRect(
            x: 0,
            y: verticalOffset,
            width: imageSize.width,
            height: imageSize.height
        )
    }

    private static func utf16Length(of text: String) -> Int {
        NSString(string: text).length
    }

    private static func utf16Length(
        for content: [NotesSemanticDocument.InlineSegment]
    ) -> Int {
        content.reduce(into: 0) { partialResult, segment in
            if segment.text.isEmpty {
                let linkLength = segment.link.map { utf16Length(of: $0.url) } ?? 0
                partialResult += linkLength
            } else {
                partialResult += utf16Length(of: segment.text)
            }
        }
    }

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

    nonisolated private static func notePlatformCapHeight(_ font: NotePlatformFont) -> CGFloat {
        #if os(iOS)
        return font.capHeight
        #elseif os(macOS)
        return font.capHeight
        #endif
    }

    private static func blockType(
        for run: AttributedString.Runs.Run,
        in attributed: AttributedString
    ) -> NotesSemanticDocument.BlockType {
        NoteTextBlockResolution.resolvedBlockType(for: run, in: attributed)
    }

    private static func applyBridgedRunAttributes(
        for run: AttributedString.Runs.Run,
        nsRange: NSRange,
        in attributed: AttributedString,
        mutable: NSMutableAttributedString,
        baseFontSize: CGFloat
    ) {
        let blockType = blockType(for: run, in: attributed)
        let swiftTraits = noteSwiftUIFontTraits(
            from: noteExplicitSwiftUIFont(from: run.attributes)
        )
        let monospaced = noteExplicitPlatformFont(from: run.attributes)
            .map { notePlatformFontTraits(from: $0).monospaced } ?? false

        mutable.addAttribute(
            .font,
            value: bridgedPlatformFont(
                for: run,
                blockType: blockType,
                baseFontSize: baseFontSize,
                swiftTraits: swiftTraits,
                monospaced: monospaced
            ),
            range: nsRange
        )
        mutable.addAttribute(
            .paragraphStyle,
            value: run.paragraphStyle ?? paragraphStyle(for: blockType, baseFontSize: baseFontSize),
            range: nsRange
        )
        applyDecorationAttributes(for: run, nsRange: nsRange, mutable: mutable)
        if run.noteChecklistCompletion == true {
            mutable.addAttribute(
                .foregroundColor,
                value: checklistCompletedPlatformTextColor,
                range: nsRange
            )
        }
    }

    private static func bridgedPlatformFont(
        for run: AttributedString.Runs.Run,
        blockType: NotesSemanticDocument.BlockType,
        baseFontSize: CGFloat,
        swiftTraits: NoteInlineFormattingTraits,
        monospaced: Bool
    ) -> NotePlatformFont {
        if run.noteBlock != nil {
            return notePlatformFont(
                baseFontSize: baseFontSize,
                blockType: blockType,
                bold: swiftTraits.bold,
                italic: swiftTraits.italic,
                inlineCode: monospaced
            )
        }

        return notePlatformFont(
            baseFontSize: noteBlockPointSize(
                baseFontSize: baseFontSize,
                blockType: blockType
            ),
            bold: swiftTraits.bold,
            italic: swiftTraits.italic,
            monospaced: monospaced
        )
    }

    private static func applyDecorationAttributes(
        for run: AttributedString.Runs.Run,
        nsRange: NSRange,
        mutable: NSMutableAttributedString
    ) {
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
    #endif

}

#if os(macOS)
@available(iOS 26.0, macOS 26.0, *)
private struct PlatformSelectableNoteReadView: NSViewRepresentable {
    let attributedContent: NSAttributedString
    let document: NotesSemanticDocument
    let maxReadableContentWidth: CGFloat
    let initialViewportOffset: CGPoint?
    let initialViewportAnchorTarget: SelectableNoteReadView.ReadActivationTarget?
    let initialViewportAnchorY: CGFloat?
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
        textView.document = document
        textView.onActivateEditing = onActivateEditing
        textView.onToggleChecklistItem = onToggleChecklistItem
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
        scrollView.documentView = nil
    }
}

@available(iOS 26.0, macOS 26.0, *)
private final class SelectableNoteReadTextView: NSTextView {
    private static let baseTextContainerInset = NSSize(
        width: NoteTextLayout.horizontalPadding,
        height: NoteTextLayout.verticalPadding
    )

    var document = NotesSemanticDocument(version: NotesSemanticDocument.currentVersion, blocks: [])
    var onActivateEditing: ((SelectableNoteReadView.ReadActivationTarget) -> Void)?
    var onToggleChecklistItem: SelectableNoteReadView.ChecklistToggleHandler?
    var maxReadableContentWidth: CGFloat = .greatestFiniteMagnitude {
        didSet { needsLayout = true }
    }
    private var didDragSelectionGesture = false
    private var lastActivationTimestamp: TimeInterval = 0

    override func layout() {
        super.layout()
        updateTextContainerInset()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        drawCodeBlockBackgrounds(in: dirtyRect)
        super.draw(dirtyRect)
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
        let point = localPoint(for: event)
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
        if let checklistToggleTarget = checklistToggleTarget(at: point),
           let onToggleChecklistItem {
            lastActivationTimestamp = ProcessInfo.processInfo.systemUptime
            DispatchQueue.main.async {
                onToggleChecklistItem(checklistToggleTarget.blockIndex, checklistToggleTarget.itemIndex)
            }
            return
        }
        let target = activationTarget(at: point)
        let canTriggerActivationNow = canTriggerActivationNow
        guard let onActivateEditing, let target, canTriggerActivationNow else { return }
        lastActivationTimestamp = ProcessInfo.processInfo.systemUptime
        DispatchQueue.main.async {
            onActivateEditing(target)
        }
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

    private func localPoint(for event: NSEvent) -> NSPoint {
        guard window != nil || event.windowNumber != 0 else {
            return event.locationInWindow
        }
        return convert(event.locationInWindow, from: nil)
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
              let readCharacterOffset = SelectableNoteReadView.characterOffsetForEditingActivation(in: self, at: point) else { return nil }
        return .characterOffset(
            SelectableNoteReadView.editingActivationCharacterOffset(
                in: document,
                readCharacterOffset: readCharacterOffset
            )
        )
    }

    private func checklistToggleTarget(at point: NSPoint) -> SelectableNoteReadView.ChecklistToggleTarget? {
        guard linkAttribute(at: point) == nil else { return nil }

        for target in SelectableNoteReadView.checklistToggleTargets(in: document) {
            guard let checkboxRect = checkboxRect(for: target.checkboxRange) else { continue }
            if checkboxHitRect(for: checkboxRect).contains(point) {
                return target
            }
        }

        return nil
    }

    private func checkboxRect(for characterRange: NSRange) -> NSRect? {
        guard let layoutManager, let textContainer else { return nil }
        textContainer.containerSize = NSSize(
            width: bounds.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: characterRange,
            actualCharacterRange: nil
        )
        guard glyphRange.length > 0 else { return nil }
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textContainerInset.width
        rect.origin.y += textContainerInset.height
        return rect
    }

    private func checkboxHitRect(for checkboxRect: NSRect) -> NSRect {
        checkboxRect.insetBy(dx: -6, dy: -6)
    }
}
#elseif os(iOS)
@available(iOS 26.0, macOS 26.0, *)
private struct PlatformSelectableNoteReadView: UIViewRepresentable {
    let attributedContent: NSAttributedString
    let document: NotesSemanticDocument
    let maxReadableContentWidth: CGFloat
    let initialViewportOffset: CGPoint?
    let initialViewportAnchorTarget: SelectableNoteReadView.ReadActivationTarget?
    let initialViewportAnchorY: CGFloat?
    let onActivateEditing: ((SelectableNoteReadView.ReadActivationTarget) -> Void)?
    let onActivateEditingWithViewport: ((SelectableNoteReadView.ReadActivationTarget, CGFloat?) -> Void)?
    let onToggleChecklistItem: SelectableNoteReadView.ChecklistToggleHandler?
    let onViewportOffsetChange: ((CGPoint) -> Void)?
    let onInitialViewportRestorationApplied: (() -> Void)?

    func makeUIView(context: Context) -> SelectableNoteReadContainerView {
        let containerView = SelectableNoteReadContainerView()
        let textView = containerView.textView
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.adjustsFontForContentSizeCategory = false
        textView.textFormattingConfiguration = nil
        textView.textColor = .label
        textView.textContainer.lineFragmentPadding = 0
        textView.document = document
        textView.maxReadableContentWidth = maxReadableContentWidth
        textView.initialViewportOffset = initialViewportOffset
        textView.initialViewportAnchorTarget = initialViewportAnchorTarget
        textView.initialViewportAnchorY = initialViewportAnchorY
        textView.accessibilityIdentifier = "notes-read-text-view"
        textView.linkTextAttributes = [
            .foregroundColor: UIColor.link,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        textView.onActivateEditing = onActivateEditing
        textView.onActivateEditingWithViewport = onActivateEditingWithViewport
        textView.onToggleChecklistItem = onToggleChecklistItem
        textView.onViewportOffsetChange = onViewportOffsetChange
        textView.onInitialViewportRestorationApplied = onInitialViewportRestorationApplied
        textView.attributedText = attributedContent
        textView.invalidateCodeBlockBackgroundLayout()
        containerView.onActivateEditing = onActivateEditing
        containerView.onActivateEditingWithViewport = onActivateEditingWithViewport
        containerView.onToggleChecklistItem = onToggleChecklistItem
        return containerView
    }

    func updateUIView(_ containerView: SelectableNoteReadContainerView, context: Context) {
        let readTextView = containerView.textView
        readTextView.document = document
        readTextView.maxReadableContentWidth = maxReadableContentWidth
        readTextView.initialViewportOffset = initialViewportOffset
        readTextView.initialViewportAnchorTarget = initialViewportAnchorTarget
        readTextView.initialViewportAnchorY = initialViewportAnchorY
        readTextView.onActivateEditing = onActivateEditing
        readTextView.onActivateEditingWithViewport = onActivateEditingWithViewport
        readTextView.onToggleChecklistItem = onToggleChecklistItem
        readTextView.onViewportOffsetChange = onViewportOffsetChange
        readTextView.onInitialViewportRestorationApplied = onInitialViewportRestorationApplied
        containerView.onActivateEditing = onActivateEditing
        containerView.onActivateEditingWithViewport = onActivateEditingWithViewport
        containerView.onToggleChecklistItem = onToggleChecklistItem
        if readTextView.attributedText.isEqual(to: attributedContent) == false {
            readTextView.attributedText = attributedContent
            readTextView.invalidateCodeBlockBackgroundLayout()
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

    var document = NotesSemanticDocument(version: NotesSemanticDocument.currentVersion, blocks: [])
    var onActivateEditing: ((SelectableNoteReadView.ReadActivationTarget) -> Void)?
    var onActivateEditingWithViewport: ((SelectableNoteReadView.ReadActivationTarget, CGFloat?) -> Void)?
    var onToggleChecklistItem: SelectableNoteReadView.ChecklistToggleHandler?
    var onViewportOffsetChange: ((CGPoint) -> Void)?
    var onInitialViewportRestorationApplied: (() -> Void)?
    var initialViewportOffset: CGPoint? {
        didSet {
            guard initialViewportOffset != oldValue else { return }
            guard let initialViewportOffset else { return }
            pendingInitialViewportOffset = initialViewportOffset
            pendingInitialViewportStabilitySignature = nil
            pendingPostRestorationStabilitySignature = nil
            isAwaitingPostRestorationStability = false
            isAwaitingPostRestorationQuietPeriod = false
            hasAppliedInitialViewportOffset = false
            lastAppliedInitialViewportOffset = nil
            lastRequestedInitialViewportOffset = nil
            setNeedsLayout()
        }
    }
    var initialViewportAnchorTarget: SelectableNoteReadView.ReadActivationTarget? {
        didSet {
            guard initialViewportAnchorTarget != oldValue else { return }
            guard let initialViewportAnchorTarget else { return }
            pendingInitialViewportAnchorTarget = initialViewportAnchorTarget
            pendingInitialViewportStabilitySignature = nil
            pendingPostRestorationStabilitySignature = nil
            isAwaitingPostRestorationStability = false
            isAwaitingPostRestorationQuietPeriod = false
            hasAppliedInitialViewportOffset = false
            lastAppliedInitialViewportOffset = nil
            lastRequestedInitialViewportOffset = nil
            setNeedsLayout()
        }
    }
    var initialViewportAnchorY: CGFloat? {
        didSet {
            guard initialViewportAnchorY != oldValue else { return }
            guard let initialViewportAnchorY else { return }
            pendingInitialViewportAnchorY = initialViewportAnchorY
            pendingInitialViewportStabilitySignature = nil
            pendingPostRestorationStabilitySignature = nil
            isAwaitingPostRestorationStability = false
            isAwaitingPostRestorationQuietPeriod = false
            hasAppliedInitialViewportOffset = false
            lastAppliedInitialViewportOffset = nil
            lastRequestedInitialViewportOffset = nil
            setNeedsLayout()
        }
    }
    var maxReadableContentWidth: CGFloat = .greatestFiniteMagnitude {
        didSet { setNeedsLayout() }
    }
    private var lastReportedViewportOffset: CGPoint?
    private var hasAppliedInitialViewportOffset = true
    private var isAwaitingPostRestorationStability = false
    private var isAwaitingPostRestorationQuietPeriod = false
    private var lastAppliedInitialViewportOffset: CGPoint?
    private var lastRequestedInitialViewportOffset: CGPoint?
    private var pendingInitialViewportOffset: CGPoint?
    private var pendingInitialViewportAnchorTarget: SelectableNoteReadView.ReadActivationTarget?
    private var pendingInitialViewportAnchorY: CGFloat?
    private var pendingInitialViewportStabilitySignature: InitialViewportStabilitySignature?
    private var pendingPostRestorationStabilitySignature: PostRestorationStabilitySignature?
    private var cachedCodeBlockBackgroundRects: [CGRect] = []
    private var isCodeBlockBackgroundLayoutDirty = true
    private var lastCodeBlockBackgroundLayoutBoundsWidth: CGFloat = 0
    private var lastCodeBlockBackgroundLayoutInset: UIEdgeInsets = .zero

    override var contentOffset: CGPoint {
        didSet {
            reportViewportOffsetIfNeeded()
            setNeedsDisplay()
        }
    }

    override var contentSize: CGSize {
        didSet {
            guard contentSize != oldValue else { return }
            pendingInitialViewportStabilitySignature = nil
            if isAwaitingPostRestorationStability {
                pendingPostRestorationStabilitySignature = nil
                isAwaitingPostRestorationQuietPeriod = false
            }
            applyInitialViewportOffsetIfNeeded()
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
        updateCodeBlockBackgroundLayoutState()
        applyInitialViewportOffsetIfNeeded()
        reportViewportOffsetIfNeeded()
    }

    override func draw(_ rect: CGRect) {
        drawCodeBlockBackgrounds(in: rect)
        super.draw(rect)
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

    func invalidateCodeBlockBackgroundLayout() {
        isCodeBlockBackgroundLayoutDirty = true
        cachedCodeBlockBackgroundRects = []
        setNeedsDisplay()
    }

    private func updateCodeBlockBackgroundLayoutState() {
        let widthChanged = abs(lastCodeBlockBackgroundLayoutBoundsWidth - bounds.width) > 0.5
        let insetChanged = lastCodeBlockBackgroundLayoutInset != textContainerInset
        guard widthChanged || insetChanged else { return }
        lastCodeBlockBackgroundLayoutBoundsWidth = bounds.width
        lastCodeBlockBackgroundLayoutInset = textContainerInset
        invalidateCodeBlockBackgroundLayout()
    }

    private func drawCodeBlockBackgrounds(in rect: CGRect) {
        guard attributedText.length > 0 else { return }
        let backgroundRects = resolvedCodeBlockBackgroundRects()
        guard backgroundRects.isEmpty == false else { return }

        NoteTextAppearance.codeBlockBackgroundColor.setFill()
        for backgroundRect in backgroundRects where backgroundRect.intersects(rect) {
            UIBezierPath(
                roundedRect: backgroundRect,
                cornerRadius: NoteTextAppearance.codeBlockCornerRadius
            ).fill()
        }
    }

    private func resolvedCodeBlockBackgroundRects() -> [CGRect] {
        guard isCodeBlockBackgroundLayoutDirty else { return cachedCodeBlockBackgroundRects }
        cachedCodeBlockBackgroundRects = NoteTextCodeBlockBackgroundLayout.detachedBlockRects(
            in: attributedText,
            containerWidth: bounds.width,
            textContainerInset: CGSize(
                width: textContainerInset.left,
                height: textContainerInset.top
            )
        )
        isCodeBlockBackgroundLayoutDirty = false
        return cachedCodeBlockBackgroundRects
    }

    private func reportViewportOffsetIfNeeded(force: Bool = false) {
        guard force || lastReportedViewportOffset != contentOffset else { return }
        lastReportedViewportOffset = contentOffset
        onViewportOffsetChange?(contentOffset)
    }

    private func applyInitialViewportOffsetIfNeeded() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let restoration = resolvedInitialViewportRestoration()
        guard let restoration else {
            if hasPendingInitialViewportRestoration { return }
            hasAppliedInitialViewportOffset = true
            return
        }
        let needsOffsetUpdate =
            abs(contentOffset.x - restoration.offset.x) > 0.5
                || abs(contentOffset.y - restoration.offset.y) > 0.5
        if needsOffsetUpdate {
            super.setContentOffset(restoration.offset, animated: false)
            pendingInitialViewportStabilitySignature = nil
            pendingPostRestorationStabilitySignature = nil
            isAwaitingPostRestorationStability = false
            isAwaitingPostRestorationQuietPeriod = false
            lastAppliedInitialViewportOffset = restoration.offset
            lastRequestedInitialViewportOffset = restoration.requestedOffset
            hasAppliedInitialViewportOffset = false
            return
        }
        if lastAppliedInitialViewportOffset != restoration.offset {
            lastAppliedInitialViewportOffset = restoration.offset
        }
        if lastRequestedInitialViewportOffset != restoration.requestedOffset {
            lastRequestedInitialViewportOffset = restoration.requestedOffset
        }
        let stabilitySignature = InitialViewportStabilitySignature(
            offset: restoration.offset,
            contentSize: contentSize,
            boundsSize: bounds.size
        )
        if pendingInitialViewportStabilitySignature != stabilitySignature {
            pendingInitialViewportStabilitySignature = stabilitySignature
            DispatchQueue.main.async { [weak self] in
                self?.applyInitialViewportOffsetIfNeeded()
            }
            return
        }
        guard hasAppliedInitialViewportOffset == false else { return }
        pendingInitialViewportStabilitySignature = nil
        hasAppliedInitialViewportOffset = true
        lastRequestedInitialViewportOffset = nil
        pendingInitialViewportOffset = nil
        pendingInitialViewportAnchorTarget = nil
        pendingInitialViewportAnchorY = nil
        reportViewportOffsetIfNeeded(force: true)
        scheduleInitialViewportRestorationAppliedIfStable()
    }

    private struct InitialViewportRestoration {
        let mode: String
        let offset: CGPoint
        let requestedOffset: CGPoint
        let viewportAnchorY: String
    }

    private struct InitialViewportStabilitySignature: Equatable {
        let offset: CGPoint
        let contentSize: CGSize
        let boundsSize: CGSize
    }

    private struct PostRestorationStabilitySignature: Equatable {
        let offset: CGPoint
        let contentSize: CGSize
        let boundsSize: CGSize
    }

    private var hasPendingInitialViewportRestoration: Bool {
        pendingInitialViewportOffset != nil
            || pendingInitialViewportAnchorTarget != nil
            || pendingInitialViewportAnchorY != nil
    }

    private func scheduleInitialViewportRestorationAppliedIfStable() {
        let stabilitySignature = PostRestorationStabilitySignature(
            offset: contentOffset,
            contentSize: contentSize,
            boundsSize: bounds.size
        )
        if isAwaitingPostRestorationStability == false {
            isAwaitingPostRestorationStability = true
            pendingPostRestorationStabilitySignature = stabilitySignature
            isAwaitingPostRestorationQuietPeriod = false
            DispatchQueue.main.async { [weak self] in
                self?.scheduleInitialViewportRestorationAppliedIfStable()
            }
            return
        }
        if pendingPostRestorationStabilitySignature != stabilitySignature {
            pendingPostRestorationStabilitySignature = stabilitySignature
            isAwaitingPostRestorationQuietPeriod = false
            DispatchQueue.main.async { [weak self] in
                self?.scheduleInitialViewportRestorationAppliedIfStable()
            }
            return
        }
        guard isAwaitingPostRestorationQuietPeriod == false else { return }
        isAwaitingPostRestorationQuietPeriod = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            let currentSignature = PostRestorationStabilitySignature(
                offset: self.contentOffset,
                contentSize: self.contentSize,
                boundsSize: self.bounds.size
            )
            guard self.isAwaitingPostRestorationStability,
                  self.isAwaitingPostRestorationQuietPeriod,
                  self.pendingPostRestorationStabilitySignature == stabilitySignature,
                  currentSignature == stabilitySignature
            else {
                return
            }
            self.isAwaitingPostRestorationStability = false
            self.isAwaitingPostRestorationQuietPeriod = false
            self.pendingPostRestorationStabilitySignature = nil
            self.onInitialViewportRestorationApplied?()
        }
    }

    private func resolvedInitialViewportRestoration() -> InitialViewportRestoration? {
        if let pendingInitialViewportAnchorTarget,
           let pendingInitialViewportAnchorY,
           let requestedOffset = SelectableNoteReadView.contentOffset(
                forViewportAnchorY: pendingInitialViewportAnchorY,
                in: self,
                target: pendingInitialViewportAnchorTarget
           ) {
            return InitialViewportRestoration(
                mode: pendingInitialViewportOffset == nil ? "anchor" : "anchor-preferred",
                offset: clampedContentOffset(for: requestedOffset),
                requestedOffset: requestedOffset,
                viewportAnchorY: String(format: "%.2f", pendingInitialViewportAnchorY)
            )
        }
        if lastAppliedInitialViewportOffset == nil,
           let pendingInitialViewportOffset {
            return InitialViewportRestoration(
                mode: pendingInitialViewportAnchorTarget == nil ? "offset" : "offset-bootstrap",
                offset: clampedContentOffset(for: pendingInitialViewportOffset),
                requestedOffset: pendingInitialViewportOffset,
                viewportAnchorY: pendingInitialViewportAnchorY.map {
                    String(format: "%.2f", $0)
                } ?? "nil"
            )
        }
        if pendingInitialViewportAnchorTarget == nil || pendingInitialViewportAnchorY == nil,
           let pendingInitialViewportOffset {
            return InitialViewportRestoration(
                mode: "offset",
                offset: clampedContentOffset(for: pendingInitialViewportOffset),
                requestedOffset: pendingInitialViewportOffset,
                viewportAnchorY: "nil"
            )
        }
        return nil
    }

    private func clampedContentOffset(for proposedOffset: CGPoint) -> CGPoint {
        let minimumX = -adjustedContentInset.left
        let minimumY = -adjustedContentInset.top
        let maximumX = max(
            contentSize.width + adjustedContentInset.right - bounds.width,
            minimumX
        )
        let maximumY = max(
            contentSize.height + adjustedContentInset.bottom - bounds.height,
            minimumY
        )
        return CGPoint(
            x: min(max(proposedOffset.x, minimumX), maximumX),
            y: min(max(proposedOffset.y, minimumY), maximumY)
        )
    }

    private func linkAttribute(at point: CGPoint) -> Any? {
        guard attributedText.length > 0 else { return nil }
        guard let position = closestPosition(to: point) else { return nil }
        let characterIndex = min(
            max(offset(from: beginningOfDocument, to: position), 0),
            attributedText.length
        )
        guard characterIndex < attributedText.length,
              let characterStart = self.position(from: beginningOfDocument, offset: characterIndex),
              let characterEnd = self.position(from: characterStart, offset: 1),
              let characterRange = textRange(from: characterStart, to: characterEnd) else {
            return nil
        }
        let characterRect = firstRect(for: characterRange)
        guard characterRect.isNull == false,
              characterRect.insetBy(dx: -1, dy: -1).contains(point) else {
            return nil
        }
        return attributedText.attribute(.link, at: characterIndex, effectiveRange: nil)
    }

    func activationTarget(at point: CGPoint) -> SelectableNoteReadView.ReadActivationTarget? {
        guard linkAttribute(at: point) == nil,
              let readCharacterOffset = SelectableNoteReadView.characterOffsetForEditingActivation(in: self, at: point) else { return nil }
        return .characterOffset(
            SelectableNoteReadView.editingActivationCharacterOffset(
                in: document,
                readCharacterOffset: readCharacterOffset
            )
        )
    }

    func checklistToggleTarget(at point: CGPoint) -> SelectableNoteReadView.ChecklistToggleTarget? {
        guard linkAttribute(at: point) == nil else { return nil }

        for target in SelectableNoteReadView.checklistToggleTargets(in: document) {
            guard let checkboxRect = checkboxRect(for: target.checkboxRange) else { continue }
            if checkboxHitRect(for: checkboxRect).contains(point) {
                return target
            }
        }

        return nil
    }

    func activationViewportAnchorY(
        at point: CGPoint,
        target: SelectableNoteReadView.ReadActivationTarget
    ) -> CGFloat? {
        SelectableNoteReadView.viewportAnchorYForEditingActivation(
            in: self,
            target: target,
            fallbackPoint: point
        )
    }

    private func checkboxRect(for characterRange: NSRange) -> CGRect? {
        var combinedRect: CGRect?
        for characterIndex in characterRange.location..<(characterRange.location + characterRange.length) {
            guard let start = position(from: beginningOfDocument, offset: characterIndex) else {
                return nil
            }
            let characterRect = resolvedCharacterRect(
                at: start,
                nextPosition: position(from: start, offset: 1)
            )
            guard characterRect.isNull == false, characterRect.isEmpty == false else { return nil }
            combinedRect = combinedRect?.union(characterRect) ?? characterRect
        }
        return combinedRect
    }

    private func resolvedCharacterRect(
        at start: UITextPosition,
        nextPosition: UITextPosition?
    ) -> CGRect {
        if let nextPosition,
           let textRange = textRange(from: start, to: nextPosition) {
            let firstRect = firstRect(for: textRange)
            if firstRect.isNull == false, firstRect.isEmpty == false {
                return firstRect
            }
        }
        return caretRect(for: start)
    }

    private func checkboxHitRect(for checkboxRect: CGRect) -> CGRect {
        checkboxRect.insetBy(dx: -8, dy: -8)
    }
}

@available(iOS 26.0, macOS 26.0, *)
private final class SelectableNoteReadContainerView: UIView, UIGestureRecognizerDelegate {
    let textView = SelectableNoteReadTextView()
    var onActivateEditing: ((SelectableNoteReadView.ReadActivationTarget) -> Void)?
    var onActivateEditingWithViewport: ((SelectableNoteReadView.ReadActivationTarget, CGFloat?) -> Void)?
    var onToggleChecklistItem: SelectableNoteReadView.ChecklistToggleHandler?

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
        if let checklistToggleTarget = textView.checklistToggleTarget(at: point),
           let onToggleChecklistItem {
            onToggleChecklistItem(checklistToggleTarget.blockIndex, checklistToggleTarget.itemIndex)
            return
        }
        guard let target = textView.activationTarget(at: point) else { return }
        if let onActivateEditingWithViewport {
            onActivateEditingWithViewport(
                target,
                textView.activationViewportAnchorY(at: point, target: target)
            )
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
    static func viewportAnchorYForEditingActivation(
        in textView: UITextView,
        target: ReadActivationTarget,
        fallbackPoint: CGPoint? = nil
    ) -> CGFloat? {
        let visibleViewport = CGRect(
            origin: textView.contentOffset,
            size: textView.bounds.size
        ).inset(by: textView.adjustedContentInset)
        let viewportHeight = visibleViewport.height
        guard viewportHeight > 0 else { return nil }
        if case .characterOffset(let offset) = target,
           let position = textView.position(from: textView.beginningOfDocument, offset: offset) {
            let anchorY = textView.caretRect(for: position).midY - visibleViewport.minY
            if anchorY >= 0, anchorY <= viewportHeight {
                return anchorY
            }
        }
        if let fallbackPoint {
            let viewportMinY = textView.contentOffset.y + textView.adjustedContentInset.top
            return min(max(fallbackPoint.y - viewportMinY, 0), viewportHeight)
        }
        return nil
    }

    static func contentOffset(
        forViewportAnchorY viewportAnchorY: CGFloat,
        in textView: UITextView,
        target: ReadActivationTarget
    ) -> CGPoint? {
        let viewportHeight = textView.bounds.inset(by: textView.adjustedContentInset).height
        guard viewportHeight > 0 else { return nil }

        let clampedViewportAnchorY = min(max(viewportAnchorY, 0), viewportHeight)
        let targetPosition: UITextPosition?
        switch target {
        case .start:
            targetPosition = textView.beginningOfDocument
        case .characterOffset(let offset):
            targetPosition = textView.position(from: textView.beginningOfDocument, offset: offset)
        }
        guard let targetPosition else { return nil }

        let targetCaretRect = textView.caretRect(for: targetPosition)
        return CGPoint(
            x: textView.contentOffset.x,
            y: targetCaretRect.midY - clampedViewportAnchorY - textView.adjustedContentInset.top
        )
    }

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
// swiftlint:enable type_body_length
#endif
