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
        let blockKey = NSAttributedString.Key(NoteTextBlockAttribute.name)
        let fullRange = NSRange(location: 0, length: attributedText.length)
        guard fullRange.length > 0 else { return [] }

        layoutManager.ensureLayout(for: textContainer)

        var rects: [CGRect] = []
        attributedText.enumerateAttribute(blockKey, in: fullRange) { value, range, _ in
            guard range.length > 0,
                  let rawValue = (value as? NSString) as String?,
                  rawValue == NotesSemanticDocument.BlockType.codeBlock.rawValue else {
                return
            }

            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }

            var blockRect: CGRect?
            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { lineFragmentRect, _, _, _, _ in
                let rect = lineFragmentRect.offsetBy(dx: textContainerInset.width, dy: textContainerInset.height)
                blockRect = blockRect?.union(rect) ?? rect
            }

            if let blockRect {
                rects.append(blockRect.integral)
            }
        }

        return rects
    }
}
