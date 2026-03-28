import Foundation

@available(iOS 26.0, macOS 26.0, *)
extension SelectableNoteReadView {
    struct ChecklistToggleTarget: Equatable {
        let blockIndex: Int
        let itemIndex: Int
        let checkboxRange: NSRange
    }

    static func checklistToggleTarget(
        in document: NotesSemanticDocument,
        characterOffset: Int
    ) -> ChecklistToggleTarget? {
        var offset = 0
        for (blockIndex, block) in document.blocks.enumerated() {
            if blockIndex > 0 {
                offset += 1
            }

            if let target = checklistToggleTargetInCurrentBlock(
                block,
                blockIndex: blockIndex,
                characterOffset: characterOffset,
                startingAt: offset
            ) {
                return target
            }

            offset = advancedOffset(
                for: block,
                startingAt: offset
            )
        }
        return nil
    }

    private static func checklistToggleTargetInCurrentBlock(
        _ block: NotesSemanticDocument.Block,
        blockIndex: Int,
        characterOffset: Int,
        startingAt offset: Int
    ) -> ChecklistToggleTarget? {
        guard block.type == .checklist else { return nil }
        let children = block.children ?? []
        var runningOffset = offset
        for (itemIndex, child) in children.enumerated() {
            if itemIndex > 0 {
                runningOffset += 1
            }
            let checkboxRange = NSRange(location: runningOffset + 2, length: 3)
            if NSLocationInRange(characterOffset, checkboxRange) {
                return ChecklistToggleTarget(
                    blockIndex: blockIndex,
                    itemIndex: itemIndex,
                    checkboxRange: checkboxRange
                )
            }
            runningOffset += 6 + inlineTextLength(for: child.content)
        }
        return nil
    }

    private static func advancedOffset(
        for block: NotesSemanticDocument.Block,
        startingAt offset: Int
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
                runningOffset += 6 + inlineTextLength(for: child.content)
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

    private static func inlineTextLength(
        for content: [NotesSemanticDocument.InlineSegment]
    ) -> Int {
        content.reduce(into: 0) { partialResult, segment in
            if segment.text.isEmpty {
                let linkLength = segment.link.map { NSString(string: $0.url).length } ?? 0
                partialResult += linkLength
            } else {
                partialResult += NSString(string: segment.text).length
            }
        }
    }

    private static func orderedListPrefixLength(for itemIndex: Int) -> Int {
        NSString(string: "\(itemIndex + 1).\t").length
    }
}
