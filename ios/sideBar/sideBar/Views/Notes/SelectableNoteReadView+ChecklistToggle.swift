import Foundation

@available(iOS 26.0, macOS 26.0, *)
extension SelectableNoteReadView {
    private static let checklistReadPrefixLength = 2
    private static let checklistEditorPrefixLength = 6
    private static let blockquoteReadPrefixLength = 0
    private static let blockquoteEditorPrefixLength = 2

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
                checklistPrefixLength: checklistReadPrefixLength,
                blockquotePrefixLength: blockquoteReadPrefixLength
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
                checklistPrefixLength: checklistReadPrefixLength,
                blockquotePrefixLength: blockquoteReadPrefixLength
            )
            editorOffset = advancedOffset(
                for: block,
                startingAt: editorOffset,
                checklistPrefixLength: checklistEditorPrefixLength,
                blockquotePrefixLength: blockquoteEditorPrefixLength
            )
        }

        return editorOffset
    }

    static func readViewportAnchorTarget(
        in document: NotesSemanticDocument,
        editorTarget: ReadActivationTarget
    ) -> ReadActivationTarget {
        switch editorTarget {
        case .start:
            return .start
        case .characterOffset(let offset):
            return .characterOffset(
                readViewportCharacterOffset(
                    in: document,
                    editorCharacterOffset: offset
                )
            )
        }
    }

    static func readViewportCharacterOffset(
        in document: NotesSemanticDocument,
        editorCharacterOffset: Int
    ) -> Int {
        var readOffset = 0
        var editorOffset = 0

        for (blockIndex, block) in document.blocks.enumerated() {
            if blockIndex > 0 {
                if editorCharacterOffset == editorOffset {
                    return readOffset
                }
                readOffset += 1
                editorOffset += 1
            }

            if let mappedOffset = readViewportCharacterOffsetInCurrentBlock(
                block,
                editorCharacterOffset: editorCharacterOffset,
                readOffset: readOffset,
                editorOffset: editorOffset
            ) {
                return mappedOffset
            }

            readOffset = advancedOffset(
                for: block,
                startingAt: readOffset,
                checklistPrefixLength: checklistReadPrefixLength,
                blockquotePrefixLength: blockquoteReadPrefixLength
            )
            editorOffset = advancedOffset(
                for: block,
                startingAt: editorOffset,
                checklistPrefixLength: checklistEditorPrefixLength,
                blockquotePrefixLength: blockquoteEditorPrefixLength
            )
        }

        return readOffset
    }

    private static func editingActivationCharacterOffsetInCurrentBlock(
        _ block: NotesSemanticDocument.Block,
        readCharacterOffset: Int,
        readOffset: Int,
        editorOffset: Int
    ) -> Int? {
        switch block.type {
        case .checklist:
            break
        case .blockquote:
            return editingActivationCharacterOffsetInBlockquote(
                block.children ?? [],
                readCharacterOffset: readCharacterOffset,
                readOffset: readOffset,
                editorOffset: editorOffset
            )
        default:
            let blockLength = advancedOffset(
                for: block,
                startingAt: readOffset,
                checklistPrefixLength: checklistReadPrefixLength,
                blockquotePrefixLength: blockquoteReadPrefixLength
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

    private static func readViewportCharacterOffsetInCurrentBlock(
        _ block: NotesSemanticDocument.Block,
        editorCharacterOffset: Int,
        readOffset: Int,
        editorOffset: Int
    ) -> Int? {
        switch block.type {
        case .checklist:
            return readViewportCharacterOffsetInChecklist(
                block.children ?? [],
                editorCharacterOffset: editorCharacterOffset,
                readOffset: readOffset,
                editorOffset: editorOffset
            )
        case .blockquote:
            return readViewportCharacterOffsetInBlockquote(
                block.children ?? [],
                editorCharacterOffset: editorCharacterOffset,
                readOffset: readOffset,
                editorOffset: editorOffset
            )
        default:
            let blockLength = advancedOffset(
                for: block,
                startingAt: editorOffset,
                checklistPrefixLength: checklistEditorPrefixLength,
                blockquotePrefixLength: blockquoteEditorPrefixLength
            ) - editorOffset
            guard editorCharacterOffset <= editorOffset + blockLength else { return nil }
            return readOffset + max(0, min(editorCharacterOffset - editorOffset, blockLength))
        }
    }

    private static func advancedOffset(
        for block: NotesSemanticDocument.Block,
        startingAt offset: Int,
        checklistPrefixLength: Int,
        blockquotePrefixLength: Int
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
            return advancedOffsetForListChildren(
                block.children ?? [],
                prefixLength: blockquotePrefixLength,
                startingAt: offset
            )
        case .divider, .table, .tableRow, .tableCell, .media, .caption, .htmlBlock:
            return offset
        }
    }

    private static func editingActivationCharacterOffsetInBlockquote(
        _ children: [NotesSemanticDocument.Block],
        readCharacterOffset: Int,
        readOffset: Int,
        editorOffset: Int
    ) -> Int? {
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
            let textStart = currentReadOffset + blockquoteReadPrefixLength
            let itemEnd = textStart + textLength

            if readCharacterOffset <= textStart {
                return currentEditorOffset + blockquoteEditorPrefixLength
            }
            if readCharacterOffset <= itemEnd {
                let logicalOffset = readCharacterOffset - textStart
                return currentEditorOffset + blockquoteEditorPrefixLength + logicalOffset
            }

            currentReadOffset = itemEnd
            currentEditorOffset += blockquoteEditorPrefixLength + textLength
        }

        return nil
    }

    private static func readViewportCharacterOffsetInChecklist(
        _ children: [NotesSemanticDocument.Block],
        editorCharacterOffset: Int,
        readOffset: Int,
        editorOffset: Int
    ) -> Int? {
        var currentReadOffset = readOffset
        var currentEditorOffset = editorOffset

        for (itemIndex, child) in children.enumerated() {
            if itemIndex > 0 {
                if editorCharacterOffset == currentEditorOffset {
                    return currentReadOffset
                }
                currentReadOffset += 1
                currentEditorOffset += 1
            }

            let textLength = inlineTextLength(for: child.content)
            let editorTextStart = currentEditorOffset + checklistEditorPrefixLength
            let editorItemEnd = editorTextStart + textLength

            if editorCharacterOffset <= editorTextStart {
                let prefixOffset = max(0, editorCharacterOffset - currentEditorOffset)
                return currentReadOffset + min(prefixOffset, checklistReadPrefixLength)
            }
            if editorCharacterOffset <= editorItemEnd {
                let logicalOffset = editorCharacterOffset - editorTextStart
                return currentReadOffset + checklistReadPrefixLength + logicalOffset
            }

            currentReadOffset += checklistReadPrefixLength + textLength
            currentEditorOffset = editorItemEnd
        }

        return nil
    }

    private static func readViewportCharacterOffsetInBlockquote(
        _ children: [NotesSemanticDocument.Block],
        editorCharacterOffset: Int,
        readOffset: Int,
        editorOffset: Int
    ) -> Int? {
        var currentReadOffset = readOffset
        var currentEditorOffset = editorOffset

        for (itemIndex, child) in children.enumerated() {
            if itemIndex > 0 {
                if editorCharacterOffset == currentEditorOffset {
                    return currentReadOffset
                }
                currentReadOffset += 1
                currentEditorOffset += 1
            }

            let textLength = inlineTextLength(for: child.content)
            let editorTextStart = currentEditorOffset + blockquoteEditorPrefixLength
            let editorItemEnd = editorTextStart + textLength

            if editorCharacterOffset <= editorTextStart {
                return currentReadOffset
            }
            if editorCharacterOffset <= editorItemEnd {
                let logicalOffset = editorCharacterOffset - editorTextStart
                return currentReadOffset + logicalOffset
            }

            currentReadOffset += textLength
            currentEditorOffset = editorItemEnd
        }

        return nil
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
