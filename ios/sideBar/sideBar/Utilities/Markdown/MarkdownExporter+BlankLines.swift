import Foundation
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
func blankLineOutput(
    in attributedString: AttributedString,
    lines: [Range<AttributedString.Index>],
    lineIndex: Int
) -> String {
    if isExplicitEditorBlankLine(
        in: attributedString,
        lines: lines,
        lineIndex: lineIndex
    ) {
        return MarkdownBlankLineMarker.htmlComment
    }
    if shouldEmitPlainBlankLine(
        in: attributedString,
        lines: lines,
        lineIndex: lineIndex
    ) {
        return ""
    }
    return MarkdownBlankLineMarker.htmlComment
}

@available(iOS 26.0, macOS 26.0, *)
private func isExplicitEditorBlankLine(
    in attributedString: AttributedString,
    lines: [Range<AttributedString.Index>],
    lineIndex: Int
) -> Bool {
    guard lines.indices.contains(lineIndex) else { return false }
    guard let lineRange = lineRangeIncludingTrailingNewline(
        in: attributedString,
        lines: lines,
        lineIndex: lineIndex
    ) else {
        return false
    }
    return attributedString.blockKind(in: lineRange) == .blankLine
}

@available(iOS 26.0, macOS 26.0, *)
private func lineRangeIncludingTrailingNewline(
    in attributedString: AttributedString,
    lines: [Range<AttributedString.Index>],
    lineIndex: Int
) -> Range<AttributedString.Index>? {
    guard lines.indices.contains(lineIndex) else { return nil }
    let lineRange = lines[lineIndex]
    if lineIndex + 1 < lines.count {
        let upper = lines[lineIndex + 1].lowerBound
        if lineRange.lowerBound < upper {
            return lineRange.lowerBound..<upper
        }
    }
    if !lineRange.isEmpty {
        return lineRange
    }
    return nil
}

@available(iOS 26.0, macOS 26.0, *)
private func shouldEmitPlainBlankLine(
    in attributedString: AttributedString,
    lines: [Range<AttributedString.Index>],
    lineIndex: Int
) -> Bool {
    guard isFirstBlankLineInRun(in: attributedString, lines: lines, lineIndex: lineIndex) else {
        return false
    }
    guard blankLineRunLength(in: attributedString, lines: lines, startIndex: lineIndex) == 1 else {
        return false
    }

    let previousBlockKind = nearestNonBlankBlockKind(
        in: attributedString,
        lines: lines,
        lineIndex: lineIndex,
        direction: -1
    )
    let nextBlockKind = nearestNonBlankBlockKind(
        in: attributedString,
        lines: lines,
        lineIndex: lineIndex,
        direction: 1
    )
    if previousBlockKind == .codeBlock && nextBlockKind == .horizontalRule {
        return true
    }

    let safeKinds: Set<BlockKind> = [
        .paragraph,
        .heading1, .heading2, .heading3, .heading4, .heading5, .heading6,
        .bulletList, .orderedList, .taskChecked, .taskUnchecked,
        .blockquote
    ]
    guard let previousBlockKind, let nextBlockKind else {
        return false
    }
    return safeKinds.contains(previousBlockKind) && safeKinds.contains(nextBlockKind)
}

@available(iOS 26.0, macOS 26.0, *)
private func isFirstBlankLineInRun(
    in attributedString: AttributedString,
    lines: [Range<AttributedString.Index>],
    lineIndex: Int
) -> Bool {
    guard lineIndex > 0 else { return true }
    return !isBlankLine(in: attributedString, lineRange: lines[lineIndex - 1])
}

@available(iOS 26.0, macOS 26.0, *)
private func blankLineRunLength(
    in attributedString: AttributedString,
    lines: [Range<AttributedString.Index>],
    startIndex: Int
) -> Int {
    var index = startIndex
    var count = 0
    while index < lines.count && isBlankLine(in: attributedString, lineRange: lines[index]) {
        count += 1
        index += 1
    }
    return count
}

@available(iOS 26.0, macOS 26.0, *)
private func nearestNonBlankBlockKind(
    in attributedString: AttributedString,
    lines: [Range<AttributedString.Index>],
    lineIndex: Int,
    direction: Int
) -> BlockKind? {
    guard direction == -1 || direction == 1 else {
        return nil
    }

    var index = lineIndex + direction
    while index >= 0 && index < lines.count {
        let lineRange = lines[index]
        if !isBlankLine(in: attributedString, lineRange: lineRange) {
            return normalizedBlockKindForLine(in: attributedString, lineRange: lineRange)
        }
        index += direction
    }

    return nil
}

@available(iOS 26.0, macOS 26.0, *)
private func isBlankLine(
    in attributedString: AttributedString,
    lineRange: Range<AttributedString.Index>
) -> Bool {
    normalizedBlockKindForLine(in: attributedString, lineRange: lineRange) == .blankLine
}

@available(iOS 26.0, macOS 26.0, *)
private func normalizedBlockKindForLine(
    in attributedString: AttributedString,
    lineRange: Range<AttributedString.Index>
) -> BlockKind {
    let lineText = filteredText(from: attributedString[lineRange])
    let rawBlockKind = attributedString.blockKind(in: lineRange) ?? .paragraph
    if rawBlockKind == .paragraph && lineText.isEmpty {
        return .blankLine
    }
    return rawBlockKind
}
