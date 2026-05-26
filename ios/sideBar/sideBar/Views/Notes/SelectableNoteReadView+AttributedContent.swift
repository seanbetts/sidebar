import SwiftUI
import sideBarShared
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@available(iOS 26.0, macOS 26.0, *)
extension SelectableNoteReadView {
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
        removeBlockquotePrefixes(in: mutable)
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
    private static var blockquotePlatformTextColor: UIColor {
        NoteTextAppearance.blockquoteTextColor
    }
    #elseif os(macOS)
    private static var defaultPlatformTextColor: NSColor { .labelColor }
    private static var checklistCompletedPlatformTextColor: NSColor {
        NoteTextAppearance.checklistCompletedTextColor
    }
    private static var blockquotePlatformTextColor: NSColor {
        NoteTextAppearance.blockquoteTextColor
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

    private static func removeBlockquotePrefixes(in mutable: NSMutableAttributedString) {
        let blockKey = NSAttributedString.Key(NoteTextBlockAttribute.name)
        let boundaryKey = NSAttributedString.Key(NoteTextStructuralBoundaryAttribute.name)
        let plainText = mutable.string as NSString
        guard plainText.length > 0 else { return }

        var replacementRanges: [NSRange] = []
        var location = 0

        while location < plainText.length {
            let paragraphRange = plainText.paragraphRange(for: NSRange(location: location, length: 0))
            if paragraphRange.length >= 2,
               plainText.substring(with: NSRange(location: paragraphRange.location, length: 2)) == "> ",
               (mutable.attribute(blockKey, at: paragraphRange.location, effectiveRange: nil) as? NSString) as String? ==
                NotesSemanticDocument.BlockType.blockquote.rawValue,
               (mutable.attribute(boundaryKey, at: paragraphRange.location, effectiveRange: nil) as? NSNumber)?.boolValue != true {
                replacementRanges.append(NSRange(location: paragraphRange.location, length: 2))
            }
            location = NSMaxRange(paragraphRange)
        }

        for range in replacementRanges.reversed() {
            mutable.deleteCharacters(in: range)
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
        let appIcon: AppIcon = isChecked ? AppIcon.Markdown.taskCompleted : AppIcon.Markdown.taskIncomplete
        return UIImage(appIcon: appIcon)?
            .withConfiguration(configuration)
            .withTintColor(color, renderingMode: .alwaysOriginal) ?? UIImage()
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
        let appIcon: AppIcon = isChecked ? AppIcon.Markdown.taskCompleted : AppIcon.Markdown.taskIncomplete
        guard let symbol = NSImage(appIcon: appIcon)?
            .withSymbolConfiguration(configuration) else {
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
        } else if blockType == .blockquote {
            mutable.addAttribute(
                .foregroundColor,
                value: blockquotePlatformTextColor,
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
}
