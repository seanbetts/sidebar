import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@available(iOS 26.0, macOS 26.0, *)
extension SelectableNoteReadView {
    private static let checklistDisplayPrefixLength = 2
    private static let checklistLogicalPrefixLength = 6

    private struct ChecklistDisplayMarker {
        let range: NSRange
        let isChecked: Bool
    }

    private static var checklistCompletionAttributeKey: NSAttributedString.Key {
        NSAttributedString.Key(NoteTextChecklistCompletionAttribute.name)
    }

    private static var checklistBlockAttributeKey: NSAttributedString.Key {
        NSAttributedString.Key(NoteTextBlockAttribute.name)
    }

    static func bridgedPlatformEditorAttributedString(
        from attributed: AttributedString,
        document: NotesSemanticDocument,
        baseFontSize: CGFloat
    ) -> NSAttributedString {
        let mutable = NSMutableAttributedString(
            attributedString: bridgedPlatformAttributedString(
                from: attributed,
                baseFontSize: baseFontSize
            )
        )
        replaceChecklistMarkersWithAttachments(
            in: mutable,
            document: document,
            baseFontSize: baseFontSize
        )
        return mutable
    }

    static func editorDisplaySelectedRange(
        in document: NotesSemanticDocument,
        logicalSelectedRange: NSRange
    ) -> NSRange {
        let lower = checklistCharacterOffset(
            in: document,
            sourceOffset: logicalSelectedRange.location,
            sourcePrefixLength: checklistLogicalPrefixLength,
            targetPrefixLength: checklistDisplayPrefixLength
        )
        let upper = checklistCharacterOffset(
            in: document,
            sourceOffset: logicalSelectedRange.location + logicalSelectedRange.length,
            sourcePrefixLength: checklistLogicalPrefixLength,
            targetPrefixLength: checklistDisplayPrefixLength
        )
        return NSRange(location: lower, length: max(0, upper - lower))
    }

    static func logicalEditorSelectedRange(
        fromDisplaySelectedRange displayRange: NSRange,
        in attributedText: NSAttributedString
    ) -> NSRange {
        logicalEditorSelectedRange(
            fromDisplaySelectedRange: displayRange,
            in: attributedText,
            document: nil
        )
    }

    static func logicalEditorSelectedRange(
        fromDisplaySelectedRange displayRange: NSRange,
        in attributedText: NSAttributedString,
        document: NotesSemanticDocument?
    ) -> NSRange {
        let lower = logicalEditorCharacterOffset(
            fromDisplayOffset: displayRange.location,
            in: attributedText,
            document: document
        )
        let upper = logicalEditorCharacterOffset(
            fromDisplayOffset: displayRange.location + displayRange.length,
            in: attributedText,
            document: document
        )
        return NSRange(location: lower, length: max(0, upper - lower))
    }

    static func expandingChecklistEditorMarkers(
        in attributedText: NSAttributedString
    ) -> NSAttributedString {
        expandingChecklistEditorMarkers(in: attributedText, document: nil)
    }

    static func expandingChecklistEditorMarkers(
        in attributedText: NSAttributedString,
        document: NotesSemanticDocument?
    ) -> NSAttributedString {
        let markers = checklistDisplayMarkers(in: attributedText, document: document)
        guard markers.isEmpty == false else { return attributedText }

        let mutable = NSMutableAttributedString(attributedString: attributedText)
        for marker in markers.reversed() {
            let safeLocation = max(0, min(marker.range.location, max(0, mutable.length - 1)))
            let sourceAttributes = mutable.length > 0
                ? mutable.attributes(at: safeLocation, effectiveRange: nil)
                : [:]
            var prefixAttributes = sourceAttributes
            prefixAttributes.removeValue(forKey: .attachment)
            prefixAttributes[checklistCompletionAttributeKey] = NSNumber(value: marker.isChecked)
            prefixAttributes[checklistBlockAttributeKey] = NotesSemanticDocument.BlockType.checklist.rawValue
            let prefix = NSAttributedString(
                string: marker.isChecked ? "- [x] " : "- [ ] ",
                attributes: prefixAttributes
            )
            mutable.replaceCharacters(in: marker.range, with: prefix)
        }
        return mutable
    }

    private static func logicalEditorCharacterOffset(
        fromDisplayOffset displayOffset: Int,
        in attributedText: NSAttributedString,
        document: NotesSemanticDocument?
    ) -> Int {
        let markers = checklistDisplayMarkers(in: attributedText, document: document)
        let plainText = attributedText.string as NSString
        var delta = 0

        for marker in markers {
            let displayPrefixStart = marker.range.location
            let displayPrefixEnd = marker.range.location + marker.range.length
            let logicalPrefixEnd = displayPrefixStart + delta + checklistLogicalPrefixLength

            if displayOffset <= displayPrefixStart {
                return displayOffset + delta
            }
            if displayOffset <= displayPrefixEnd {
                return logicalPrefixEnd
            }
            if displayOffset == displayPrefixEnd + 1,
               displayPrefixEnd < plainText.length,
               plainText.substring(with: NSRange(location: displayPrefixEnd, length: 1)) == "\n" {
                return logicalPrefixEnd
            }

            delta += checklistLogicalPrefixLength - marker.range.length
        }

        return displayOffset + delta
    }

    private static func checklistCharacterOffset(
        in document: NotesSemanticDocument,
        sourceOffset: Int,
        sourcePrefixLength: Int,
        targetPrefixLength: Int
    ) -> Int {
        var runningSourceOffset = 0
        var runningTargetOffset = 0

        for (blockIndex, block) in document.blocks.enumerated() {
            if blockIndex > 0 {
                if sourceOffset == runningSourceOffset {
                    return runningTargetOffset
                }
                runningSourceOffset += 1
                runningTargetOffset += 1
            }

            if let mappedOffset = checklistCharacterOffsetInCurrentBlock(
                block,
                sourceOffset: sourceOffset,
                blockSourceOffset: runningSourceOffset,
                blockTargetOffset: runningTargetOffset,
                sourcePrefixLength: sourcePrefixLength,
                targetPrefixLength: targetPrefixLength
            ) {
                return mappedOffset
            }

            runningSourceOffset = advancedOffset(
                for: block,
                startingAt: runningSourceOffset,
                checklistPrefixLength: sourcePrefixLength
            )
            runningTargetOffset = advancedOffset(
                for: block,
                startingAt: runningTargetOffset,
                checklistPrefixLength: targetPrefixLength
            )
        }

        return runningTargetOffset
    }

    private static func checklistCharacterOffsetInCurrentBlock(
        _ block: NotesSemanticDocument.Block,
        sourceOffset: Int,
        blockSourceOffset: Int,
        blockTargetOffset: Int,
        sourcePrefixLength: Int,
        targetPrefixLength: Int
    ) -> Int? {
        guard block.type == .checklist else {
            let blockLength = advancedOffset(
                for: block,
                startingAt: blockSourceOffset,
                checklistPrefixLength: sourcePrefixLength
            ) - blockSourceOffset
            guard sourceOffset <= blockSourceOffset + blockLength else { return nil }
            return blockTargetOffset + max(0, sourceOffset - blockSourceOffset)
        }

        let children = block.children ?? []
        var currentSourceOffset = blockSourceOffset
        var currentTargetOffset = blockTargetOffset

        for (itemIndex, child) in children.enumerated() {
            if itemIndex > 0 {
                if sourceOffset == currentSourceOffset {
                    return currentTargetOffset
                }
                currentSourceOffset += 1
                currentTargetOffset += 1
            }

            let textLength = inlineTextLength(for: child.content)
            let sourceTextStart = currentSourceOffset + sourcePrefixLength
            let sourceItemEnd = sourceTextStart + textLength

            if sourceOffset <= sourceTextStart {
                return currentTargetOffset + targetPrefixLength
            }
            if sourceOffset <= sourceItemEnd {
                let contentOffset = sourceOffset - sourceTextStart
                return currentTargetOffset + targetPrefixLength + contentOffset
            }

            currentSourceOffset = sourceItemEnd
            currentTargetOffset += targetPrefixLength + textLength
        }

        return nil
    }

    private static func checklistDisplayMarkers(
        in attributedText: NSAttributedString
    ) -> [ChecklistDisplayMarker] {
        checklistDisplayMarkers(in: attributedText, document: nil)
    }

    private static func checklistDisplayMarkers(
        in attributedText: NSAttributedString,
        document: NotesSemanticDocument?
    ) -> [ChecklistDisplayMarker] {
        guard attributedText.length > 0 else { return [] }

        let plainText = attributedText.string as NSString
        var markers: [ChecklistDisplayMarker] = []
        attributedText.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributedText.length)
        ) { value, range, _ in
            guard let attachment = value as? NSTextAttachment else { return }
            let isChecked = (attachment as? ChecklistMarkerTextAttachment)?.isChecked
                ?? (attributedText.attribute(
                    checklistCompletionAttributeKey,
                    at: range.location,
                    effectiveRange: nil
                ) as? NSNumber)?.boolValue
            guard let isChecked else {
                return
            }

            let hasTrailingSpace = range.location + 1 < plainText.length
                && plainText.substring(with: NSRange(location: range.location + 1, length: 1)) == " "
            markers.append(
                ChecklistDisplayMarker(
                    range: NSRange(location: range.location, length: hasTrailingSpace ? 2 : 1),
                    isChecked: isChecked
                )
            )
        }
        if markers.isEmpty == false || document == nil {
            return markers
        }
        return checklistDisplayMarkers(in: attributedText, document: document!)
    }

    private static func checklistDisplayMarkers(
        in attributedText: NSAttributedString,
        document: NotesSemanticDocument
    ) -> [ChecklistDisplayMarker] {
        var markers: [ChecklistDisplayMarker] = []
        var offset = 0

        for (blockIndex, block) in document.blocks.enumerated() {
            if blockIndex > 0 {
                offset += 1
            }

            guard block.type == .checklist else {
                offset = advancedOffset(
                    for: block,
                    startingAt: offset,
                    checklistPrefixLength: checklistDisplayPrefixLength
                )
                continue
            }

            let children = block.children ?? []
            for (itemIndex, child) in children.enumerated() {
                if itemIndex > 0 {
                    offset += 1
                }
                guard offset < attributedText.length else { break }
                let availableLength = min(
                    checklistDisplayPrefixLength,
                    max(0, attributedText.length - offset)
                )
                markers.append(
                    ChecklistDisplayMarker(
                        range: NSRange(location: offset, length: availableLength),
                        isChecked: child.checked == true
                    )
                )
                offset += checklistDisplayPrefixLength + inlineTextLength(for: child.content)
            }
        }

        return markers
    }

    private static func advancedOffset(
        for block: NotesSemanticDocument.Block,
        startingAt offset: Int,
        checklistPrefixLength: Int
    ) -> Int {
        switch block.type {
        case .title, .paragraph, .heading, .subheading, .listItem, .codeBlock:
            return offset + inlineTextLength(for: block.content)
        case .unorderedList:
            return advancedOffsetForListChildren(
                block.children ?? [],
                prefixLength: 2,
                startingAt: offset
            )
        case .orderedList:
            let children = block.children ?? []
            var runningOffset = offset
            for (itemIndex, child) in children.enumerated() {
                if itemIndex > 0 {
                    runningOffset += 1
                }
                runningOffset += orderedListPrefixLength(for: itemIndex) + inlineTextLength(for: child.content)
            }
            return runningOffset
        case .checklist:
            let children = block.children ?? []
            var runningOffset = offset
            for (itemIndex, child) in children.enumerated() {
                if itemIndex > 0 {
                    runningOffset += 1
                }
                runningOffset += checklistPrefixLength + inlineTextLength(for: child.content)
            }
            return runningOffset
        case .blockquote:
            return offset + blockquotePlainTextLength(for: block.children ?? [])
        case .table, .tableRow, .tableCell, .media, .caption, .htmlBlock:
            return offset
        }
    }

    private static func advancedOffsetForListChildren(
        _ children: [NotesSemanticDocument.Block],
        prefixLength: Int,
        startingAt offset: Int
    ) -> Int {
        var runningOffset = offset
        for (itemIndex, child) in children.enumerated() {
            if itemIndex > 0 {
                runningOffset += 1
            }
            runningOffset += prefixLength + inlineTextLength(for: child.content)
        }
        return runningOffset
    }

    private static func orderedListPrefixLength(for itemIndex: Int) -> Int {
        "\(itemIndex + 1). ".utf16.count
    }

    private static func inlineTextLength(
        for content: [NotesSemanticDocument.InlineSegment]
    ) -> Int {
        content.reduce(into: 0) { partialResult, segment in
            partialResult += NSString(string: segment.text).length
        }
    }

    private static func blockquotePlainTextLength(
        for blocks: [NotesSemanticDocument.Block]
    ) -> Int {
        let plainText = NotesSemanticDocumentProjection.plainText(
            from: NotesSemanticDocument(
                version: NotesSemanticDocument.currentVersion,
                blocks: [
                    .init(type: .blockquote, children: blocks)
                ]
            )
        )
        return NSString(string: plainText).length
    }
}
