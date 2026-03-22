import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@available(iOS 26.0, macOS 26.0, *)
enum NoteCodeBlockBackgroundLayout {
    static let cornerRadius: CGFloat = 8
    private static let horizontalPadding: CGFloat = 8
    private static let verticalPadding: CGFloat = 4

    static func rects(
        textStorage: NSTextStorage?,
        layoutManager: NSLayoutManager?,
        textContainer: NSTextContainer?,
        insetX: CGFloat,
        insetY: CGFloat
    ) -> [CGRect] {
        guard let textStorage, let layoutManager, let textContainer else { return [] }
        guard textStorage.length > 0 else { return [] }

        layoutManager.ensureLayout(for: textContainer)
        let fullRange = NSRange(location: 0, length: textStorage.length)
        var blockRects: [CGRect] = []

        textStorage.enumerateAttribute(
            NSAttributedString.Key(NoteTextBlockAttribute.name),
            in: fullRange
        ) { value, characterRange, _ in
            guard blockType(for: value) == .codeBlock else { return }
            guard characterRange.length > 0 else { return }

            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: characterRange,
                actualCharacterRange: nil
            )
            guard glyphRange.length > 0 else { return }

            var minX = CGFloat.greatestFiniteMagnitude
            var maxX = -CGFloat.greatestFiniteMagnitude
            var minY = CGFloat.greatestFiniteMagnitude
            var maxY = -CGFloat.greatestFiniteMagnitude

            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { lineFragmentRect, usedRect, _, _, _ in
                let fragmentRect = lineFragmentRect.standardized
                let textRect = usedRect.standardized
                minX = min(minX, fragmentRect.minX - horizontalPadding)
                maxX = max(maxX, textRect.maxX + horizontalPadding)
                minY = min(minY, fragmentRect.minY - verticalPadding)
                maxY = max(maxY, fragmentRect.maxY + verticalPadding)
            }

            guard minX.isFinite, maxX.isFinite, minY.isFinite, maxY.isFinite else { return }
            blockRects.append(
                CGRect(
                    x: insetX + minX,
                    y: insetY + minY,
                    width: maxX - minX,
                    height: maxY - minY
                ).integral
            )
        }

        return blockRects
    }

    private static func blockType(for rawValue: Any?) -> NotesSemanticDocument.BlockType? {
        switch rawValue {
        case let value as String:
            return NoteTextBlockAttribute.blockType(from: value)
        case let value as NSString:
            return NoteTextBlockAttribute.blockType(from: value as String)
        default:
            return nil
        }
    }
}
