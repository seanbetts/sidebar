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
    var initialViewportOffset: CGPoint?
    var initialViewportAnchorTarget: ReadActivationTarget?
    var initialViewportAnchorY: CGFloat?
    var onActivateEditing: ((ReadActivationTarget) -> Void)?
    var onActivateEditingWithViewport: ((ReadActivationTarget, CGFloat?) -> Void)?
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
            maxReadableContentWidth: maxContentWidth,
            initialViewportOffset: initialViewportOffset,
            initialViewportAnchorTarget: initialViewportAnchorTarget,
            initialViewportAnchorY: initialViewportAnchorY,
            onActivateEditing: onActivateEditing,
            onActivateEditingWithViewport: onActivateEditingWithViewport,
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

        let insertionIndex = textView.characterIndexForInsertion(at: point)
        return min(max(insertionIndex, 0), plainText.length)
    }
    #endif
}

#if os(macOS)
@available(iOS 26.0, macOS 26.0, *)
private struct PlatformSelectableNoteReadView: NSViewRepresentable {
    let attributedContent: NSAttributedString
    let maxReadableContentWidth: CGFloat
    let initialViewportOffset: CGPoint?
    let initialViewportAnchorTarget: SelectableNoteReadView.ReadActivationTarget?
    let initialViewportAnchorY: CGFloat?
    let onActivateEditing: ((SelectableNoteReadView.ReadActivationTarget) -> Void)?
    let onActivateEditingWithViewport: ((SelectableNoteReadView.ReadActivationTarget, CGFloat?) -> Void)?
    let onViewportOffsetChange: ((CGPoint) -> Void)?
    let onInitialViewportRestorationApplied: (() -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let textView = SelectableNoteReadView.makePlatformTextView(
            attributedContent: attributedContent,
            onActivateEditing: onActivateEditing
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
    private static let baseTextContainerInset = NSSize(
        width: NoteTextLayout.horizontalPadding,
        height: NoteTextLayout.verticalPadding
    )

    var onActivateEditing: ((SelectableNoteReadView.ReadActivationTarget) -> Void)?
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
    let initialViewportOffset: CGPoint?
    let initialViewportAnchorTarget: SelectableNoteReadView.ReadActivationTarget?
    let initialViewportAnchorY: CGFloat?
    let onActivateEditing: ((SelectableNoteReadView.ReadActivationTarget) -> Void)?
    let onActivateEditingWithViewport: ((SelectableNoteReadView.ReadActivationTarget, CGFloat?) -> Void)?
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
        textView.onViewportOffsetChange = onViewportOffsetChange
        textView.onInitialViewportRestorationApplied = onInitialViewportRestorationApplied
        textView.attributedText = attributedContent
        containerView.onActivateEditing = onActivateEditing
        containerView.onActivateEditingWithViewport = onActivateEditingWithViewport
        return containerView
    }

    func updateUIView(_ containerView: SelectableNoteReadContainerView, context: Context) {
        let readTextView = containerView.textView
        readTextView.maxReadableContentWidth = maxReadableContentWidth
        readTextView.initialViewportOffset = initialViewportOffset
        readTextView.initialViewportAnchorTarget = initialViewportAnchorTarget
        readTextView.initialViewportAnchorY = initialViewportAnchorY
        readTextView.onActivateEditing = onActivateEditing
        readTextView.onActivateEditingWithViewport = onActivateEditingWithViewport
        readTextView.onViewportOffsetChange = onViewportOffsetChange
        readTextView.onInitialViewportRestorationApplied = onInitialViewportRestorationApplied
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
    private var lastDebugLayoutSummary: String?
    private var debugTrackedActivationTarget: SelectableNoteReadView.ReadActivationTarget?

    override var contentOffset: CGPoint {
        didSet {
            reportViewportOffsetIfNeeded()
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
        applyInitialViewportOffsetIfNeeded()
        reportViewportOffsetIfNeeded()
        guard NotesIOSParityDebugTrace.isEnabled else { return }
        let summary = [
            "instance=\(NotesIOSParityDebugTrace.objectIdentity(self))",
            "restoration={pendingOffset:\(String(describing: pendingInitialViewportOffset)),"
                + "pendingTarget:\(String(describing: pendingInitialViewportAnchorTarget)),"
                + "pendingAnchorY:\(pendingInitialViewportAnchorY.map { String(format: "%.2f", $0) } ?? "nil"),"
                + "applied:\(hasAppliedInitialViewportOffset),"
                + "lastApplied:\(String(describing: lastAppliedInitialViewportOffset)),"
                + "lastRequested:\(String(describing: lastRequestedInitialViewportOffset))}",
            NotesIOSParityDebugTrace.activationTargetSummary(
                in: self,
                target: debugTrackedActivationTarget
            ),
            NotesIOSParityDebugTrace.textViewSummary(self)
        ].joined(separator: " ")
        guard summary != lastDebugLayoutSummary else { return }
        lastDebugLayoutSummary = summary
        NotesIOSParityDebugTrace.log(
            "SelectableNoteReadView.SelectableNoteReadTextView.layoutSubviews",
            details: summary
        )
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
            debugTrackedActivationTarget = pendingInitialViewportAnchorTarget
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
              let characterOffset = SelectableNoteReadView.characterOffsetForEditingActivation(in: self, at: point) else { return nil }
        return .characterOffset(characterOffset)
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
#endif
