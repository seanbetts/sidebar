import Foundation
import SwiftUI
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
func serializedNoteContent(_ viewModel: NativeNoteEditorViewModel) -> String {
    var exportContent = viewModel.attributedContent
    let selection = viewModel.selectionSnapshot(in: exportContent)
    _ = viewModel.removeInjectedListMarkers(in: &exportContent, selection: selection)
    let constrained = NoteTextFormattingDefinition().constrainedDocument(exportContent)
    return noteTextSerializedContent(from: constrained)
}

@available(iOS 26.0, macOS 26.0, *)
private func noteTextSerializedContent(from text: AttributedString) -> String {
    var lines: [String] = []
    var serializationState = NoteTextSerializationState()

    for range in noteTextLineRanges(in: text) {
        let plainLine = String(text[range].characters)
        let blockKind = text.blockKind(in: range) ?? .paragraph
        if blockKind == .horizontalRule,
           let previous = lines.last,
           !previous.isEmpty {
            lines.append("")
        }
        let serialized = noteTextSerializedLine(
            plainLine: plainLine,
            blockKind: blockKind,
            range: range,
            text: text,
            state: &serializationState
        )
        lines.append(serialized)
    }

    return lines.joined(separator: "\n")
}

@available(iOS 26.0, macOS 26.0, *)
private struct NoteTextSerializationState {
    var orderedOrdinal = 0
    var previousListDepth: Int?
}

@available(iOS 26.0, macOS 26.0, *)
private func noteTextSerializedLine(
    plainLine: String,
    blockKind: BlockKind,
    range: Range<AttributedString.Index>,
    text: AttributedString,
    state: inout NoteTextSerializationState
) -> String {
    switch blockKind {
    case .blockquote:
        state.orderedOrdinal = 0
        state.previousListDepth = nil
        return "> \(plainLine)"
    case .horizontalRule:
        state.orderedOrdinal = 0
        state.previousListDepth = nil
        return "---"
    case .bulletList:
        state.orderedOrdinal = 0
        state.previousListDepth = nil
        return "- \(plainLine)"
    case .orderedList:
        let listDepth = text[range].listDepth
        if state.previousListDepth == listDepth {
            state.orderedOrdinal += 1
        } else {
            state.orderedOrdinal = 1
        }
        state.previousListDepth = listDepth
        return "\(state.orderedOrdinal). \(plainLine)"
    case .taskUnchecked:
        state.orderedOrdinal = 0
        state.previousListDepth = nil
        return "- [ ] \(plainLine)"
    case .taskChecked:
        state.orderedOrdinal = 0
        state.previousListDepth = nil
        if noteTextLineIsStruckThrough(text, range: range), !plainLine.isEmpty {
            return "- [x] ~~\(plainLine)~~"
        }
        return "- [x] \(plainLine)"
    default:
        state.orderedOrdinal = 0
        state.previousListDepth = nil
        return plainLine
    }
}

@available(iOS 26.0, macOS 26.0, *)
private func noteTextLineRanges(in text: AttributedString) -> [Range<AttributedString.Index>] {
    var ranges: [Range<AttributedString.Index>] = []
    var start = text.startIndex
    var cursor = text.startIndex

    while cursor < text.endIndex {
        if text.characters[cursor].isNewline {
            ranges.append(start..<cursor)
            start = text.index(afterCharacter: cursor)
            cursor = start
        } else {
            cursor = text.index(afterCharacter: cursor)
        }
    }

    if start <= text.endIndex {
        ranges.append(start..<text.endIndex)
    }

    return ranges
}

@available(iOS 26.0, macOS 26.0, *)
private func noteTextLineIsStruckThrough(
    _ text: AttributedString,
    range: Range<AttributedString.Index>
) -> Bool {
    let runs = text[range].runs.filter { $0.listMarker != true }
    guard !runs.isEmpty else { return false }
    return runs.allSatisfy { $0.strikethroughStyle == .single }
}
