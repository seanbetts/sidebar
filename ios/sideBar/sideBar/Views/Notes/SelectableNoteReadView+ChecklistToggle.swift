import Foundation

@available(iOS 26.0, macOS 26.0, *)
extension SelectableNoteReadView {
    private static let checklistReadPrefixLength = 2
    private static let checklistEditorPrefixLength = 6

    struct ChecklistToggleTarget: Equatable {
        let blockIndex: Int
        let itemIndex: Int
        let checkboxRange: NSRange
    }

    static func checklistToggleTarget(
        in document: NotesSemanticDocument,
        characterOffset: Int
    ) -> ChecklistToggleTarget? {
        checklistToggleTargets(in: document).first { target in
            NSLocationInRange(characterOffset, target.checkboxRange)
        }
    }

    static func checklistToggleTargets(
        in document: NotesSemanticDocument
    ) -> [ChecklistToggleTarget] {
        var targets: [ChecklistToggleTarget] = []
        var offset = 0
        for (blockIndex, block) in document.blocks.enumerated() {
            if blockIndex > 0 {
                offset += 1
            }

            targets.append(
                contentsOf: checklistToggleTargetsInCurrentBlock(
                block,
                blockIndex: blockIndex,
                characterOffset: nil,
                startingAt: offset
            ))

            offset = advancedOffset(
                for: block,
                startingAt: offset,
                checklistPrefixLength: checklistReadPrefixLength
            )
        }
        return targets
    }

    private static func checklistToggleTargetsInCurrentBlock(
        _ block: NotesSemanticDocument.Block,
        blockIndex: Int,
        characterOffset: Int?,
        startingAt offset: Int
    ) -> [ChecklistToggleTarget] {
        guard block.type == .checklist else { return [] }
        let children = block.children ?? []
        var runningOffset = offset
        var targets: [ChecklistToggleTarget] = []
        for (itemIndex, child) in children.enumerated() {
            if itemIndex > 0 {
                runningOffset += 1
            }
            let target = ChecklistToggleTarget(
                    blockIndex: blockIndex,
                    itemIndex: itemIndex,
                    checkboxRange: NSRange(location: runningOffset, length: 1)
                )
            if let characterOffset {
                if NSLocationInRange(characterOffset, target.checkboxRange) {
                    return [target]
                }
            } else {
                targets.append(target)
            }
            runningOffset += checklistReadPrefixLength + inlineTextLength(for: child.content)
        }
        return targets
    }

    static func editingActivationCharacterOffset(
        in document: NotesSemanticDocument,
        readCharacterOffset: Int
    ) -> Int {
        var readOffset = 0
        var editorOffset = 0

        for (blockIndex, block) in document.blocks.enumerated() {
            if blockIndex > 0 {
                if readCharacterOffset == readOffset {
                    return editorOffset
                }
                readOffset += 1
                editorOffset += 1
            }

            if let mappedOffset = editingActivationCharacterOffsetInCurrentBlock(
                block,
                readCharacterOffset: readCharacterOffset,
                readOffset: readOffset,
                editorOffset: editorOffset
            ) {
                return mappedOffset
            }

            readOffset = advancedOffset(
                for: block,
                startingAt: readOffset,
                checklistPrefixLength: checklistReadPrefixLength
            )
            editorOffset = advancedOffset(
                for: block,
                startingAt: editorOffset,
                checklistPrefixLength: checklistEditorPrefixLength
            )
        }

        return editorOffset
    }

    private static func editingActivationCharacterOffsetInCurrentBlock(
        _ block: NotesSemanticDocument.Block,
        readCharacterOffset: Int,
        readOffset: Int,
        editorOffset: Int
    ) -> Int? {
        guard block.type == .checklist else {
            let blockLength = advancedOffset(
                for: block,
                startingAt: readOffset,
                checklistPrefixLength: checklistReadPrefixLength
            ) - readOffset
            guard readCharacterOffset <= readOffset + blockLength else { return nil }
            return editorOffset + max(0, readCharacterOffset - readOffset)
        }

        let children = block.children ?? []
        var currentReadOffset = readOffset
        var currentEditorOffset = editorOffset

        for (itemIndex, child) in children.enumerated() {
            if itemIndex > 0 {
                if readCharacterOffset == currentReadOffset {
                    return currentEditorOffset
                }
                currentReadOffset += 1
                currentEditorOffset += 1
            }

            let textLength = inlineTextLength(for: child.content)
            let textStart = currentReadOffset + checklistReadPrefixLength
            let itemEnd = textStart + textLength

            if readCharacterOffset <= textStart {
                return currentEditorOffset + checklistEditorPrefixLength
            }
            if readCharacterOffset <= itemEnd {
                let logicalOffset = readCharacterOffset - textStart
                return currentEditorOffset + checklistEditorPrefixLength + logicalOffset
            }

            currentReadOffset = itemEnd
            currentEditorOffset += checklistEditorPrefixLength + textLength
        }

        return nil
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
