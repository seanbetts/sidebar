#if os(iOS)
import Foundation
import UIKit

@available(iOS 26.0, *)
enum NotesIOSParityDebugTrace {
    private static let envKey = "SIDEBAR_NOTES_IOS_PARITY_DEBUG"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment[envKey] == "1"
    }

    static func log(_ event: String, details: @autoclosure () -> String = "") {
        guard isEnabled else { return }
        let renderedDetails = details()
        if renderedDetails.isEmpty {
            print("[NotesIOSDebug] \(event)")
        } else {
            print("[NotesIOSDebug] \(event) \(renderedDetails)")
        }
    }

    static func documentSummary(_ document: NotesSemanticDocument, maxBlocks: Int = 4) -> String {
        let blocks = document.blocks.prefix(maxBlocks).map { block -> String in
            let preview = NotesSemanticDocumentProjection.plainText(
                from: NotesSemanticDocument(blocks: [block])
            )
            .replacingOccurrences(of: "\n", with: "\\n")
            .prefix(24)
            return "\(block.type.rawValue)=\(preview)"
        }
        let suffix = document.blocks.count > maxBlocks ? ",..." : ""
        return "blocks=\(document.blocks.count) [\(blocks.joined(separator: ", "))\(suffix)]"
    }

    static func textViewSummary(_ textView: UITextView) -> String {
        let attributedText = textView.attributedText ?? NSAttributedString()
        let sampleOffsets = paragraphSampleOffsets(in: attributedText.string)
        let sampleSummary = sampleOffsets.map { sampleDescription(in: textView, offset: $0) }
            .joined(separator: "; ")
        return [
            "frame=\(describe(textView.frame))",
            "bounds=\(describe(textView.bounds))",
            "contentOffset=\(describe(textView.contentOffset))",
            "contentSize=\(describe(textView.contentSize))",
            "contentInset=\(describe(textView.contentInset))",
            "adjustedContentInset=\(describe(textView.adjustedContentInset))",
            "textContainerInset=\(describe(textView.textContainerInset))",
            "textLength=\(attributedText.length)",
            "samples=[\(sampleSummary)]"
        ].joined(separator: " ")
    }

    private static func paragraphSampleOffsets(in string: String, limit: Int = 4) -> [Int] {
        let utf16 = string.utf16
        guard utf16.isEmpty == false else { return [] }

        var offsets: [Int] = [0]
        var currentOffset = 0
        for scalar in utf16 {
            currentOffset += 1
            guard scalar == 10 else { continue }
            guard currentOffset < utf16.count else { break }
            offsets.append(currentOffset)
            if offsets.count == limit { break }
        }
        return offsets
    }

    private static func sampleDescription(in textView: UITextView, offset: Int) -> String {
        let attributedText = textView.attributedText ?? NSAttributedString()
        guard offset < attributedText.length else { return "\(offset)=out-of-bounds" }

        let font = attributedText.attribute(.font, at: offset, effectiveRange: nil) as? UIFont
        let paragraphStyle =
            attributedText.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle
        let fontTraits = font.map(notePlatformFontTraits(from:)) ?? .plain
        let rectDescription: String
        if let start = textView.position(from: textView.beginningOfDocument, offset: offset),
           let end = textView.position(from: start, offset: 1),
           let range = textView.textRange(from: start, to: end) {
            rectDescription = describe(textView.firstRect(for: range))
        } else {
            rectDescription = "nil"
        }

        return [
            "offset=\(offset)",
            "font=\(font.map { String(format: "%.2f", $0.pointSize) } ?? "nil")",
            "bold=\(fontTraits.bold)",
            "italic=\(fontTraits.italic)",
            "mono=\(fontTraits.monospaced)",
            "spacing=\(String(format: "%.2f", paragraphStyle?.paragraphSpacing ?? -1))",
            "headIndent=\(String(format: "%.2f", paragraphStyle?.headIndent ?? -1))",
            "rect=\(rectDescription)"
        ].joined(separator: ",")
    }

    private static func describe(_ point: CGPoint) -> String {
        "{x:\(format(point.x)),y:\(format(point.y))}"
    }

    private static func describe(_ size: CGSize) -> String {
        "{w:\(format(size.width)),h:\(format(size.height))}"
    }

    private static func describe(_ rect: CGRect) -> String {
        "{x:\(format(rect.origin.x)),y:\(format(rect.origin.y)),w:\(format(rect.width)),h:\(format(rect.height))}"
    }

    private static func describe(_ insets: UIEdgeInsets) -> String {
        "{t:\(format(insets.top)),l:\(format(insets.left)),b:\(format(insets.bottom)),r:\(format(insets.right))}"
    }

    private static func format(_ value: CGFloat) -> String {
        String(format: "%.2f", value)
    }
}
#endif
