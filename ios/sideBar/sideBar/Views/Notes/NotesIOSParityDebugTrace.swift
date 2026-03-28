#if os(iOS)
import Foundation
import UIKit

@MainActor
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
        let paragraphSummary = paragraphSummaries(in: textView).joined(separator: "; ")
        let selectionSummary = selectedRangeSummary(in: textView)
        return [
            "frame=\(describe(textView.frame))",
            "bounds=\(describe(textView.bounds))",
            "contentOffset=\(describe(textView.contentOffset))",
            "contentSize=\(describe(textView.contentSize))",
            "contentInset=\(describe(textView.contentInset))",
            "adjustedContentInset=\(describe(textView.adjustedContentInset))",
            "textContainerInset=\(describe(textView.textContainerInset))",
            "textLength=\(attributedText.length)",
            "selection=\(selectionSummary)",
            "samples=[\(sampleSummary)]",
            "paragraphs=[\(paragraphSummary)]"
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

    private static func paragraphSummaries(in textView: UITextView, limit: Int = 8) -> [String] {
        let attributedText = textView.attributedText ?? NSAttributedString()
        let string = attributedText.string as NSString
        guard string.length > 0 else { return [] }

        var summaries: [String] = []
        var location = 0
        while location < string.length, summaries.count < limit {
            let paragraphRange = string.paragraphRange(for: NSRange(location: location, length: 0))
            let sampleLocation = min(paragraphRange.location, max(attributedText.length - 1, 0))
            let paragraphStyle =
                attributedText.attribute(.paragraphStyle, at: sampleLocation, effectiveRange: nil) as? NSParagraphStyle
            let noteBlock = attributedText.attribute(
                NSAttributedString.Key(NoteTextBlockAttribute.name),
                at: sampleLocation,
                effectiveRange: nil
            ) as? String
            let preview = string.substring(with: paragraphRange)
                .replacingOccurrences(of: "\n", with: "\\n")
                .prefix(18)
            let rectDescription: String
            if let start = textView.position(from: textView.beginningOfDocument, offset: paragraphRange.location),
               let end = textView.position(from: start, offset: max(1, min(paragraphRange.length, 1))),
               let range = textView.textRange(from: start, to: end) {
                rectDescription = describe(textView.firstRect(for: range))
            } else {
                rectDescription = "nil"
            }
            summaries.append(
                [
                    "loc=\(paragraphRange.location)",
                    "len=\(paragraphRange.length)",
                    "block=\(noteBlock ?? "nil")",
                    "before=\(String(format: "%.2f", paragraphStyle?.paragraphSpacingBefore ?? -1))",
                    "after=\(String(format: "%.2f", paragraphStyle?.paragraphSpacing ?? -1))",
                    "line=\(String(format: "%.2f", paragraphStyle?.lineSpacing ?? -1))",
                    "preview=\(preview)",
                    "rect=\(rectDescription)"
                ].joined(separator: ",")
            )
            location = NSMaxRange(paragraphRange)
        }
        return summaries
    }

    private static func selectedRangeSummary(in textView: UITextView) -> String {
        let attributedText = textView.attributedText ?? NSAttributedString()
        let selectedRange = textView.selectedRange
        guard selectedRange.location != NSNotFound, selectedRange.location <= attributedText.length else {
            return "nil"
        }

        let sampleLocation = min(selectedRange.location, max(attributedText.length - 1, 0))
        let paragraphSummary = paragraphSummary(
            in: textView,
            containingOffset: sampleLocation
        ) ?? "nil"
        let selectionRectDescription = selectionRectInContentCoordinates(in: textView)
            .map(describe) ?? "nil"
        let selectionViewportAnchorY = currentSelectionViewportAnchorY(in: textView)
            .map { String(format: "%.2f", $0) } ?? "nil"

        return [
            "range={loc:\(selectedRange.location),len:\(selectedRange.length)}",
            "rect=\(selectionRectDescription)",
            "anchorY=\(selectionViewportAnchorY)",
            "paragraph=\(paragraphSummary)"
        ].joined(separator: ",")
    }

    private static func paragraphSummary(
        in textView: UITextView,
        containingOffset offset: Int
    ) -> String? {
        let attributedText = textView.attributedText ?? NSAttributedString()
        let string = attributedText.string as NSString
        guard string.length > 0, offset < string.length else { return nil }

        let paragraphRange = string.paragraphRange(for: NSRange(location: offset, length: 0))
        let sampleLocation = min(paragraphRange.location, max(attributedText.length - 1, 0))
        let paragraphStyle =
            attributedText.attribute(.paragraphStyle, at: sampleLocation, effectiveRange: nil) as? NSParagraphStyle
        let noteBlock = attributedText.attribute(
            NSAttributedString.Key(NoteTextBlockAttribute.name),
            at: sampleLocation,
            effectiveRange: nil
        ) as? String
        let preview = string.substring(with: paragraphRange)
            .replacingOccurrences(of: "\n", with: "\\n")
            .prefix(18)
        let rectDescription: String
        if let start = textView.position(from: textView.beginningOfDocument, offset: paragraphRange.location),
           let end = textView.position(from: start, offset: max(1, min(paragraphRange.length, 1))),
           let range = textView.textRange(from: start, to: end) {
            rectDescription = describe(textView.firstRect(for: range))
        } else {
            rectDescription = "nil"
        }

        return [
            "loc=\(paragraphRange.location)",
            "len=\(paragraphRange.length)",
            "block=\(noteBlock ?? "nil")",
            "before=\(String(format: "%.2f", paragraphStyle?.paragraphSpacingBefore ?? -1))",
            "after=\(String(format: "%.2f", paragraphStyle?.paragraphSpacing ?? -1))",
            "line=\(String(format: "%.2f", paragraphStyle?.lineSpacing ?? -1))",
            "preview=\(preview)",
            "rect=\(rectDescription)"
        ].joined(separator: ",")
    }

    private static func currentSelectionViewportAnchorY(in textView: UITextView) -> CGFloat? {
        guard let selectionRect = selectionRectInContentCoordinates(in: textView) else {
            return nil
        }
        let visibleViewport = textView.bounds.inset(by: textView.adjustedContentInset)
        guard visibleViewport.height > 0 else { return nil }
        return selectionRect.midY - visibleViewport.minY
    }

    private static func selectionRectInContentCoordinates(in textView: UITextView) -> CGRect? {
        let selectedRange = textView.selectedRange
        guard selectedRange.location != NSNotFound else { return nil }

        if selectedRange.length == 0,
           let position = textView.position(from: textView.beginningOfDocument, offset: selectedRange.location) {
            return textView.caretRect(for: position)
        }

        guard let textRange = textRange(in: textView, for: selectedRange) else { return nil }
        let rect = textView.firstRect(for: textRange)
        guard rect.isNull == false, rect.isEmpty == false else { return nil }
        return rect
    }

    private static func textRange(in textView: UITextView, for range: NSRange) -> UITextRange? {
        guard let start = textView.position(from: textView.beginningOfDocument, offset: range.location) else {
            return nil
        }
        guard let end = textView.position(from: start, offset: range.length) else {
            return nil
        }
        return textView.textRange(from: start, to: end)
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
