import Foundation
import CoreGraphics
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@available(iOS 26.0, macOS 26.0, *)
enum NoteTextDividerDecorationLayout {
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

        let availableWidth = max(textContainer.size.width - (NoteTextAppearance.dividerHorizontalInset * 2), 0)
        guard availableWidth > 0 else { return [] }

        var rects: [CGRect] = []
        attributedText.enumerateAttributes(in: fullRange) { attributes, range, _ in
            guard range.length > 0 else { return }
            let isDividerBoundary =
                (attributes[blockKey] as? NSString) as String? == NotesSemanticDocument.BlockType.divider.rawValue &&
                (attributes[boundaryKey] as? NSNumber)?.boolValue == true
            guard isDividerBoundary else { return }

            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: range,
                actualCharacterRange: nil
            )
            guard glyphRange.length > 0 else { return }

            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { lineFragmentRect, _, _, _, _ in
                let ruleRect = CGRect(
                    x: textContainerInset.width + NoteTextAppearance.dividerHorizontalInset,
                    y: lineFragmentRect.midY + textContainerInset.height - (NoteTextAppearance.dividerRuleThickness / 2),
                    width: availableWidth,
                    height: NoteTextAppearance.dividerRuleThickness
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

    private static func integralized(_ rect: CGRect) -> CGRect {
        CGRect(
            x: floor(rect.minX),
            y: floor(rect.minY),
            width: ceil(rect.maxX) - floor(rect.minX),
            height: ceil(rect.maxY) - floor(rect.minY)
        )
    }
}
