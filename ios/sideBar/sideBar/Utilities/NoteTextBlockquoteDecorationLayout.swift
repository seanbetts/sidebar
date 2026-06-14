import Foundation
import CoreGraphics
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@available(iOS 26.0, macOS 26.0, *)
enum NoteTextBlockquoteDecorationLayout {
    static let ruleWidth: CGFloat = 3
    static let ruleGap: CGFloat = 6

    static func ruleRects(
        in attributedText: NSAttributedString,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        textContainerInset: CGSize
    ) -> [CGRect] {
        let blockKey = NSAttributedString.Key(NoteTextBlockAttribute.name)
        let boundaryKey = NSAttributedString.Key(NoteTextStructuralBoundaryAttribute.name)
        let fullRange = NSRange(location: 0, length: attributedText.length)
        guard fullRange.length > 0 else { return [] }

        layoutManager.ensureLayout(for: textContainer)

        var rects: [CGRect] = []
        for range in contiguousBlockquoteContentRanges(
            in: attributedText,
            fullRange: fullRange,
            blockKey: blockKey,
            boundaryKey: boundaryKey
        ) {
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: range,
                actualCharacterRange: nil
            )
            guard glyphRange.length > 0 else { continue }

            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, _, _ in
                let ruleRect = CGRect(
                    x: usedRect.minX + textContainerInset.width - ruleGap - ruleWidth,
                    y: usedRect.minY + textContainerInset.height,
                    width: ruleWidth,
                    height: usedRect.height
                )
                rects.append(integralized(ruleRect))
            }
        }

        return rects
    }

    #if canImport(UIKit)
    static func detachedRuleRects(
        in attributedText: NSAttributedString,
        containerWidth: CGFloat,
        textContainerInset: CGSize
    ) -> [CGRect] {
        let availableWidth = max(containerWidth - (textContainerInset.width * 2), 0)
        guard availableWidth > 0, attributedText.length > 0 else { return [] }

        let textStorage = NSTextStorage(attributedString: attributedText)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            size: CGSize(width: availableWidth, height: .greatestFiniteMagnitude)
        )
        textContainer.lineFragmentPadding = 0
        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = false
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        return ruleRects(
            in: attributedText,
            layoutManager: layoutManager,
            textContainer: textContainer,
            textContainerInset: textContainerInset
        )
    }
    #endif

    private static func contiguousBlockquoteContentRanges(
        in attributedText: NSAttributedString,
        fullRange: NSRange,
        blockKey: NSAttributedString.Key,
        boundaryKey: NSAttributedString.Key
    ) -> [NSRange] {
        var ranges: [NSRange] = []
        var currentRange: NSRange?

        attributedText.enumerateAttributes(in: fullRange) { attributes, range, _ in
            guard range.length > 0 else { return }
            let isBlockquoteContent =
                (attributes[blockKey] as? NSString) as String? == NotesSemanticDocument.BlockType.blockquote.rawValue &&
                (attributes[boundaryKey] as? NSNumber)?.boolValue != true

            guard isBlockquoteContent else {
                if let existingRange = currentRange {
                    ranges.append(existingRange)
                    currentRange = nil
                }
                return
            }

            appendMergedRange(range, currentRange: &currentRange)
        }

        if let currentRange {
            ranges.append(currentRange)
        }

        return ranges
    }

    private static func appendMergedRange(
        _ range: NSRange?,
        currentRange: inout NSRange?
    ) {
        guard let range else {
            currentRange = nil
            return
        }

        if let existingRange = currentRange, NSMaxRange(existingRange) == range.location {
            currentRange = NSRange(
                location: existingRange.location,
                length: existingRange.length + range.length
            )
        } else {
            currentRange = range
        }
    }

    private static func integralized(_ rect: CGRect) -> CGRect {
        CGRect(
            x: floor(rect.minX),
            y: floor(rect.minY),
            width: ceil(rect.maxX) - floor(rect.minX),
            height: ceil(rect.maxY) - floor(rect.minY)
        )
    }
}
