@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeMarkdownEditorViewModel {
    func shouldRemoveSpacingBefore(
        blockKind: BlockKind?,
        previousBlockKind: BlockKind?
    ) -> Bool {
        guard let previousBlockKind, isHeading(previousBlockKind) else { return false }
        guard let blockKind else { return false }
        return blockKind == .paragraph || isListBlockKind(blockKind)
    }

    func isHeading(_ blockKind: BlockKind) -> Bool {
        headingLevel(for: blockKind) != nil
    }

    func orderedListOrdinals(
        in text: AttributedString,
        lines: [LineInfo]
    ) -> [Int: Int] {
        struct ListKey: Hashable {
            let identity: Int?
            let fallbackGroup: Int?
        }

        var ordinals: [Int: Int] = [:]
        var counters: [ListKey: Int] = [:]
        var fallbackGroup = 0
        var previousWasOrdered = false
        var previousDepth: Int?
        var previousIdentity: Int?

        for (index, line) in lines.enumerated() {
            let lineRange = attributedRange(for: line.range, in: text)
            let blockKind = text.blockKind(in: lineRange) ?? inferredBlockKind(from: line.text)
            guard blockKind == .orderedList else {
                previousWasOrdered = false
                previousDepth = nil
                previousIdentity = nil
                continue
            }

            let depth = max(1, text[lineRange].listDepth ?? 1)
            let identity = listIdentity(in: text, range: lineRange)
            let key: ListKey

            if let identity {
                key = ListKey(identity: identity, fallbackGroup: nil)
            } else {
                if !(previousWasOrdered && previousIdentity == nil && previousDepth == depth) {
                    fallbackGroup += 1
                }
                key = ListKey(identity: nil, fallbackGroup: fallbackGroup)
            }

            let next = (counters[key] ?? 0) + 1
            counters[key] = next
            ordinals[index] = next
            previousWasOrdered = true
            previousDepth = depth
            previousIdentity = identity
        }

        return ordinals
    }

    func listIdentity(in text: AttributedString, range: Range<AttributedString.Index>) -> Int? {
        for run in text[range].runs {
            guard let intent = run[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] else { continue }
            for component in intent.components {
                switch component.kind {
                case .orderedList, .unorderedList:
                    return component.identity
                default:
                    break
                }
            }
        }
        return nil
    }

    func normalizeListMarkers(
        in text: inout AttributedString,
        lines: [LineInfo],
        listOrdinals: [Int: Int],
        selection: SelectionSnapshot
    ) -> SelectionSnapshot {
        var snapshot = selection

        for (index, line) in lines.enumerated().reversed() {
            let showPrefix = shouldShowPrefix(for: line.range, selection: selection)
            let lineRange = attributedRange(for: line.range, in: text)
            let blockKind = text.blockKind(in: lineRange) ?? inferredBlockKind(from: line.text)
            let lineStyle = text[lineRange].paragraphStyle
            let markerRanges = listMarkerRanges(in: text, lineRange: lineRange)
            let markerRange = markerRanges.first

            if let updatedSnapshot = removeOrphanedListMarkers(
                blockKind: blockKind,
                markerRanges: markerRanges,
                text: &text,
                snapshot: snapshot
            ) {
                snapshot = updatedSnapshot
                continue
            }

            guard let blockKind, isListBlockKind(blockKind) else { continue }

            let depth = max(1, text[lineRange].listDepth ?? 1)
            let prefixInfo = listPrefixInfo(in: line.text, depth: depth, blockKind: blockKind)
            let insertionOffset = line.range.lowerBound + prefixInfo.blockquoteLength
            let listPrefixRange = markerRange == nil ? prefixInfo.listPrefixRange : nil
            let context = ListMarkerContext(
                index: index,
                line: line,
                depth: depth,
                blockKind: blockKind,
                insertionOffset: insertionOffset,
                listPrefixRange: listPrefixRange,
                markerRange: markerRange,
                lineStyle: lineStyle
            )

            if showPrefix {
                snapshot = applyCaretListPrefix(context, text: &text, snapshot: snapshot)
            } else {
                snapshot = applyReadListMarker(
                    context,
                    text: &text,
                    snapshot: snapshot,
                    listOrdinals: listOrdinals
                )
            }
        }

        return snapshot
    }

    struct ListMarkerContext {
        let index: Int
        let line: LineInfo
        let depth: Int
        let blockKind: BlockKind
        let insertionOffset: Int
        let listPrefixRange: Range<String.Index>?
        let markerRange: Range<AttributedString.Index>?
        let lineStyle: NSParagraphStyle?
    }

    func removeOrphanedListMarkers(
        blockKind: BlockKind?,
        markerRanges: [Range<AttributedString.Index>],
        text: inout AttributedString,
        snapshot: SelectionSnapshot
    ) -> SelectionSnapshot? {
        guard !markerRanges.isEmpty else { return nil }
        guard !(blockKind.map(isListBlockKind) ?? false) else { return nil }
        var updated = snapshot
        for range in markerRanges.reversed() {
            let startOffset = text.characters.distance(from: text.startIndex, to: range.lowerBound)
            let length = text.characters.distance(from: range.lowerBound, to: range.upperBound)
            text.removeSubrange(range)
            updated = adjustSnapshot(updated, removing: length, at: startOffset)
        }
        return updated
    }

    func applyCaretListPrefix(
        _ context: ListMarkerContext,
        text: inout AttributedString,
        snapshot: SelectionSnapshot
    ) -> SelectionSnapshot {
        var updated = snapshot

        if let markerRange = context.markerRange {
            let startOffset = text.characters.distance(from: text.startIndex, to: markerRange.lowerBound)
            let length = text.characters.distance(from: markerRange.lowerBound, to: markerRange.upperBound)
            text.removeSubrange(markerRange)
            updated = adjustSnapshot(updated, removing: length, at: startOffset)
        }

        if context.listPrefixRange == nil {
            let prefixText = listPrefixString(depth: context.depth, blockKind: context.blockKind)
            guard !prefixText.isEmpty else { return updated }
            guard let insertIndex = safeIndex(in: text, offset: context.insertionOffset) else { return updated }
            var insert = AttributedString(prefixText)
            let insertRange = insert.startIndex..<insert.endIndex
            insert[insertRange].blockKind = context.blockKind
            insert[insertRange].listDepth = context.depth
            if let style = context.lineStyle {
                insert[insertRange].paragraphStyle = style
            }
            text.insert(insert, at: insertIndex)
            updated = adjustSnapshot(updated, inserting: prefixText.count, at: context.insertionOffset)
        }

        return updated
    }

    func applyReadListMarker(
        _ context: ListMarkerContext,
        text: inout AttributedString,
        snapshot: SelectionSnapshot,
        listOrdinals: [Int: Int]
    ) -> SelectionSnapshot {
        var updated = snapshot

        if let listPrefixRange = context.listPrefixRange {
            let prefixStart = context.line.text.distance(from: context.line.text.startIndex, to: listPrefixRange.lowerBound)
            let prefixLength = context.line.text.distance(from: listPrefixRange.lowerBound, to: listPrefixRange.upperBound)
            let removeOffset = context.line.range.lowerBound + prefixStart
            guard let removeStart = safeIndex(in: text, offset: removeOffset),
                  let removeEnd = safeIndex(in: text, offset: removeOffset + prefixLength),
                  removeStart < removeEnd else { return updated }
            text.removeSubrange(removeStart..<removeEnd)
            updated = adjustSnapshot(updated, removing: prefixLength, at: removeOffset)
        }

        if context.markerRange == nil {
            let ordinal = listOrdinals[context.index] ?? 1
            let markerText = listMarkerString(depth: context.depth, blockKind: context.blockKind, ordinal: ordinal)
            guard !markerText.isEmpty else { return updated }
            guard let insertIndex = safeIndex(in: text, offset: context.insertionOffset) else { return updated }
            var insert = AttributedString(markerText)
            let insertRange = insert.startIndex..<insert.endIndex
            insert[insertRange].blockKind = context.blockKind
            insert[insertRange].listDepth = context.depth
            insert[insertRange].listMarker = true
            let (markerFont, markerPlatformFont) = listMarkerFont(for: context.blockKind)
            setFont(markerFont, platformFont: markerPlatformFont, in: &insert, range: insertRange)
            setForegroundColor(baseForegroundColor(for: context.blockKind), in: &insert, range: insertRange)
            setBackgroundColor(baseBackgroundColor(for: context.blockKind), in: &insert, range: insertRange)
            if let style = context.lineStyle {
                insert[insertRange].paragraphStyle = style
            }
            text.insert(insert, at: insertIndex)
            updated = adjustSnapshot(updated, inserting: markerText.count, at: context.insertionOffset)
        }

        return updated
    }

    func safeIndex(in text: AttributedString, offset: Int) -> AttributedString.Index? {
        guard offset >= 0 else { return nil }
        let count = text.characters.count
        guard offset <= count else { return nil }
        return text.index(text.startIndex, offsetByCharacters: offset)
    }

    func removeInjectedListMarkers(
        in text: inout AttributedString,
        selection: SelectionSnapshot
    ) -> SelectionSnapshot {
        let markerRanges = text.runs.compactMap { run -> Range<AttributedString.Index>? in
            run.listMarker == true ? run.range : nil
        }

        guard !markerRanges.isEmpty else { return selection }
        var updated = selection
        for range in markerRanges.reversed() {
            let startOffset = text.characters.distance(from: text.startIndex, to: range.lowerBound)
            let length = text.characters.distance(from: range.lowerBound, to: range.upperBound)
            text.removeSubrange(range)
            updated = adjustSnapshot(updated, removing: length, at: startOffset)
        }
        return updated
    }

    func listMarkerRanges(
        in text: AttributedString,
        lineRange: Range<AttributedString.Index>
    ) -> [Range<AttributedString.Index>] {
        var ranges: [Range<AttributedString.Index>] = []
        for run in text[lineRange].runs {
            guard run.listMarker == true else { continue }
            ranges.append(run.range)
        }
        return ranges
    }

    func listMarkerString(depth: Int, blockKind: BlockKind, ordinal: Int) -> String {
        let markerBody: String
        switch blockKind {
        case .orderedList:
            markerBody = "\(ordinal)."
        case .taskChecked:
            markerBody = "☑"
        case .taskUnchecked:
            markerBody = "☐"
        default:
            markerBody = "•"
        }
        switch blockKind {
        case .orderedList, .bulletList:
            return markerBody + "  "
        case .taskChecked, .taskUnchecked:
            return markerBody + " "
        default:
            return markerBody
        }
    }

    func listMarkerFont(for blockKind: BlockKind) -> (Font, PlatformFont) {
        switch blockKind {
        case .bulletList:
            let size = baseFontSize * 1.2
            return (
                .system(size: size, weight: .bold),
                platformSystemFont(size: size, weight: .bold)
            )
        case .orderedList:
            let size = baseFontSize
            #if os(iOS)
            let platformFont = UIFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
            #else
            let platformFont = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
            #endif
            return (
                .system(size: size, weight: .regular).monospacedDigit(),
                platformFont
            )
        default:
            return (baseFont(for: blockKind), platformBaseFont(for: blockKind))
        }
    }

    func platformLineHeight(for font: PlatformFont) -> CGFloat {
#if os(iOS)
        font.lineHeight
#elseif os(macOS)
        font.ascender - font.descender + font.leading
#endif
    }

    struct ListPrefixInfo {
        let blockquoteLength: Int
        let listPrefixRange: Range<String.Index>?
    }

    func listPrefixInfo(in lineText: String, depth: Int, blockKind: BlockKind?) -> ListPrefixInfo {
        let blockquoteRange = blockquotePrefixRange(in: lineText)
        let blockquoteLength = blockquoteRange.map { lineText.distance(from: lineText.startIndex, to: $0.upperBound) } ?? 0
        let listPrefixRange = listPrefixRange(in: lineText, offset: blockquoteLength)
        return ListPrefixInfo(blockquoteLength: blockquoteLength, listPrefixRange: listPrefixRange)
    }

    func blockquotePrefixRange(in lineText: String) -> Range<String.Index>? {
        let range = NSRange(location: 0, length: lineText.utf16.count)
        guard let regex = try? NSRegularExpression(pattern: #"^(?:\s*>\s*)+"#) else { return nil }
        guard let match = regex.firstMatch(in: lineText, range: range) else { return nil }
        return Range(match.range, in: lineText)
    }

    func listPrefixRange(in lineText: String, offset: Int) -> Range<String.Index>? {
        let startIndex = lineText.index(lineText.startIndex, offsetBy: min(offset, lineText.count))
        let substring = String(lineText[startIndex...])
        let patterns = [
            #"^\s*[-+*]\s+\[[ xX]\]\s"#,
            #"^\s*\d+\.\s"#,
            #"^\s*[-+*]\s"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(location: 0, length: substring.utf16.count)
            guard let match = regex.firstMatch(in: substring, range: range) else { continue }
            guard let matchRange = Range(match.range, in: substring) else { continue }
            let lower = lineText.index(startIndex, offsetBy: substring.distance(from: substring.startIndex, to: matchRange.lowerBound))
            let upper = lineText.index(startIndex, offsetBy: substring.distance(from: substring.startIndex, to: matchRange.upperBound))
            return lower..<upper
        }
        return nil
    }

    func listPrefixString(depth: Int, blockKind: BlockKind?) -> String {
        let indent = String(repeating: "  ", count: max(0, depth - 1))
        switch blockKind {
        case .orderedList:
            return indent + "1. "
        case .taskChecked:
            return indent + "- [x] "
        case .taskUnchecked:
            return indent + "- [ ] "
        default:
            return indent + "- "
        }
    }

    func adjustSnapshot(
        _ snapshot: SelectionSnapshot,
        inserting length: Int,
        at position: Int
    ) -> SelectionSnapshot {
        guard length > 0 else { return snapshot }
        switch snapshot {
        case .insertionPoint(let offset):
            return .insertionPoint(offset >= position ? offset + length : offset)
        case .ranges(let ranges):
            let updated = ranges.map { range -> Range<Int> in
                let lower = range.lowerBound >= position ? range.lowerBound + length : range.lowerBound
                let upper = range.upperBound >= position ? range.upperBound + length : range.upperBound
                return lower..<upper
            }
            return .ranges(updated)
        }
    }

    func adjustSnapshot(
        _ snapshot: SelectionSnapshot,
        removing length: Int,
        at position: Int
    ) -> SelectionSnapshot {
        guard length > 0 else { return snapshot }
        switch snapshot {
        case .insertionPoint(let offset):
            if offset >= position + length {
                return .insertionPoint(offset - length)
            }
            if offset >= position {
                return .insertionPoint(position)
            }
            return .insertionPoint(offset)
        case .ranges(let ranges):
            let updated = ranges.map { range -> Range<Int> in
                let lower = adjustOffset(range.lowerBound, removing: length, at: position)
                let upper = adjustOffset(range.upperBound, removing: length, at: position)
                return lower..<upper
            }
            return .ranges(updated)
        }
    }

    func adjustOffset(_ offset: Int, removing length: Int, at position: Int) -> Int {
        if offset >= position + length {
            return offset - length
        }
        if offset >= position {
            return position
        }
        return offset
    }
}
