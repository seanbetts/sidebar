import Foundation

@available(iOS 26.0, macOS 26.0, *)
func normalizedExportBlockKind(
    rawBlockKind: BlockKind,
    lineText: String,
    text: AttributedString,
    lines: [Range<AttributedString.Index>],
    lineIndex: Int
) -> BlockKind {
    if rawBlockKind == .paragraph && lineText.isEmpty {
        if isEmptyLineInsideCodeBlock(text: text, lines: lines, lineIndex: lineIndex) {
            return .codeBlock
        }
        return .blankLine
    }
    return rawBlockKind
}

@available(iOS 26.0, macOS 26.0, *)
private func isEmptyLineInsideCodeBlock(
    text: AttributedString,
    lines: [Range<AttributedString.Index>],
    lineIndex: Int
) -> Bool {
    guard lineIndex > 0 else { return false }
    let previousRange = lines[lineIndex - 1]
    return text.blockKind(in: previousRange) == .codeBlock
}
