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
    @AppStorage(AppStorageKeys.appTextSize) private var appTextSizeRaw = AppTextSizeOption.system.rawValue

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

    private var resolvedTextSizeOption: AppTextSizeOption {
        AppTextSizeOption.resolved(from: appTextSizeRaw)
    }

    static func makeAttributedContent(
        from document: NotesSemanticDocument,
        baseFontSize: CGFloat = NoteTextTypography.defaultBodyFontSize
    ) -> AttributedString {
        let rawContent = NotesAttributedDocumentCodec.attributedString(
            from: document,
            baseFontSize: baseFontSize
        )
        return applyingDetectedLinks(to: rawContent)
    }

    static func readBaseFontSize(for option: AppTextSizeOption) -> CGFloat {
        NoteTextTypography.defaultBodyFontSize(for: option)
    }

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

            let traits = noteInlineTraits(for: run)
            mutable.addAttribute(
                .font,
                value: notePlatformFont(
                    baseFontSize: baseFontSize,
                    bold: traits.bold,
                    italic: traits.italic
                ),
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

        mutable.removeAttribute(
            .paragraphStyle,
            range: NSRange(location: 0, length: mutable.length)
        )
        return mutable
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
        let swiftUIFontTraits = noteSwiftUIFontTraits(from: run.font)
        let platformTraits = noteBridgedPlatformFont(from: run.attributes)
            .map(notePlatformFontTraits(from:))
            ?? .plain
        return NoteInlineFormattingTraits(
            bold: swiftUIFontTraits.bold || platformTraits.bold,
            italic: swiftUIFontTraits.italic || platformTraits.italic
        )
    }

    private static func applyingDetectedLinks(to attributed: AttributedString) -> AttributedString {
        let plainText = String(attributed.characters)
        guard !plainText.isEmpty,
              let detector = try? NSDataDetector(
                types: NSTextCheckingResult.CheckingType.link.rawValue
              ) else {
            return attributed
        }

        let bridged = NSMutableAttributedString(
            attributedString: (try? NSAttributedString(attributed, including: \.noteTextEditor))
                ?? NSAttributedString(attributed)
        )
        let fullRange = NSRange(plainText.startIndex..<plainText.endIndex, in: plainText)

        detector.enumerateMatches(in: plainText, options: [], range: fullRange) { match, _, _ in
            guard let match,
                  let url = match.url,
                  match.range.location != NSNotFound else {
                return
            }
            bridged.addAttribute(.link, value: url, range: match.range)
        }

        return AttributedString(bridged)
    }

    #if os(macOS)
    static func makePlatformTextView(
        attributedContent: NSAttributedString,
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
        textView.installActivationClickRecognizerIfNeeded()
        textView.textStorage?.setAttributedString(attributedContent)
        return textView
    }
    #endif
}

#if os(macOS)
@available(iOS 26.0, macOS 26.0, *)
private struct PlatformSelectableNoteReadView: NSViewRepresentable {
    let attributedContent: NSAttributedString
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
        if textView.textStorage?.isEqual(to: attributedContent) == false {
            textView.textStorage?.setAttributedString(attributedContent)
        }
    }
}

@available(iOS 26.0, macOS 26.0, *)
private final class SelectableNoteReadTextView: NSTextView {
    var onActivateEditing: (() -> Void)?
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
        guard shouldActivateEditing(clickCount: event.clickCount, point: point) else { return }
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

    private func activateEditingIfNeeded(at point: NSPoint) {
        guard onActivateEditing != nil,
              linkAttribute(at: point) == nil,
              canTriggerActivationNow else {
            return
        }
        lastActivationTimestamp = ProcessInfo.processInfo.systemUptime
        onActivateEditing?()
    }

    private var canTriggerActivationNow: Bool {
        let now = ProcessInfo.processInfo.systemUptime
        return now - lastActivationTimestamp > 0.2
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
    let attributedContent: NSAttributedString
    let onActivateEditing: (() -> Void)?

    func makeUIView(context: Context) -> SelectableNoteReadContainerView {
        let containerView = SelectableNoteReadContainerView()
        let textView = containerView.textView
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.adjustsFontForContentSizeCategory = false
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
    var onActivateEditing: (() -> Void)?

    func shouldActivateEditing(at point: CGPoint) -> Bool {
        onActivateEditing != nil && linkAttribute(at: point) == nil
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

@available(iOS 26.0, macOS 26.0, *)
private final class SelectableNoteReadContainerView: UIView, UIGestureRecognizerDelegate {
    let textView = SelectableNoteReadTextView()
    var onActivateEditing: (() -> Void)?

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
        guard textView.shouldActivateEditing(at: point) else { return }
        onActivateEditing?()
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
#endif
