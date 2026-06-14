import Foundation
import CoreGraphics
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@available(iOS 26.0, macOS 26.0, *)
enum NoteTextCodeBlockBackgroundLayout {
    static func blockRects(
        in attributedText: NSAttributedString,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        textContainerInset: CGSize
    ) -> [CGRect] {
        blockRects(
            in: attributedText,
            layoutManager: layoutManager,
            textContainer: textContainer,
            textContainerInset: textContainerInset,
            shouldEnsureLayout: true
        )
    }

    #if canImport(UIKit)
    static func detachedBlockRects(
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

        return blockRects(
            in: attributedText,
            layoutManager: layoutManager,
            textContainer: textContainer,
            textContainerInset: textContainerInset,
            shouldEnsureLayout: true
        )
    }
    #endif

    private static func blockRects(
        in attributedText: NSAttributedString,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        textContainerInset: CGSize,
        shouldEnsureLayout: Bool
    ) -> [CGRect] {
        let blockKey = NSAttributedString.Key(NoteTextBlockAttribute.name)
        let boundaryKey = NSAttributedString.Key(NoteTextStructuralBoundaryAttribute.name)
        let fullRange = NSRange(location: 0, length: attributedText.length)
        guard fullRange.length > 0 else { return [] }

        if shouldEnsureLayout {
            layoutManager.ensureLayout(for: textContainer)
        }

        var rects: [CGRect] = []
        let codeContentRanges = contiguousCodeContentRanges(
            in: attributedText,
            fullRange: fullRange,
            blockKey: blockKey,
            boundaryKey: boundaryKey
        )

        for range in codeContentRanges {
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: range,
                actualCharacterRange: nil
            )
            guard glyphRange.length > 0 else { continue }

            var blockRect: CGRect?
            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { lineFragmentRect, usedRect, _, _, _ in
                let rect = CGRect(
                    x: lineFragmentRect.minX + textContainerInset.width,
                    y: usedRect.minY + textContainerInset.height,
                    width: lineFragmentRect.width,
                    height: usedRect.height
                )
                blockRect = blockRect?.union(rect) ?? rect
            }

            guard let blockRect else { continue }
            let paddedRect = blockRect.insetBy(
                dx: 0,
                dy: -NoteTextAppearance.codeBlockVerticalPadding
            )
            rects.append(integralized(paddedRect))
        }

        return rects
    }

    private static func contiguousCodeContentRanges(
        in attributedText: NSAttributedString,
        fullRange: NSRange,
        blockKey: NSAttributedString.Key,
        boundaryKey: NSAttributedString.Key
    ) -> [NSRange] {
        var ranges: [NSRange] = []
        var currentRange: NSRange?

        attributedText.enumerateAttributes(in: fullRange) { attributes, range, _ in
            guard range.length > 0 else { return }
            let isCodeContent =
                (attributes[blockKey] as? NSString) as String? == NotesSemanticDocument.BlockType.codeBlock.rawValue &&
                (attributes[boundaryKey] as? NSNumber)?.boolValue != true

            guard isCodeContent else {
                if let existingRange = currentRange {
                    ranges.append(existingRange)
                    currentRange = nil
                }
                return
            }

            if let existingRange = currentRange, NSMaxRange(existingRange) == range.location {
                currentRange = NSRange(
                    location: existingRange.location,
                    length: existingRange.length + range.length
                )
            } else {
                if let existingRange = currentRange {
                    ranges.append(existingRange)
                }
                currentRange = range
            }
        }

        if let existingRange = currentRange {
            ranges.append(existingRange)
        }

        return ranges
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
