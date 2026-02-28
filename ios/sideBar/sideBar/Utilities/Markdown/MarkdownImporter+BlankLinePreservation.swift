@preconcurrency import Foundation

@available(iOS 26.0, macOS 26.0, *)
func preserveAuthorBlankLines(in markdown: String) -> String {
    var lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    let hasTrailingNewline = markdown.hasSuffix("\n")
    if hasTrailingNewline, !lines.isEmpty {
        lines.removeLast() // Drop synthetic terminal line created by split().
    }

    var output: [String] = []
    var fence: CodeFence?

    for index in lines.indices {
        let line = lines[index]
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if let delimiter = codeFenceDelimiter(in: trimmed) {
            if fence == nil {
                fence = delimiter
            } else if delimiter.character == fence?.character, delimiter.length >= (fence?.length ?? 0) {
                fence = nil
            }
            output.append(line)
            continue
        }

        if fence == nil,
           line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           shouldConvertBlankLine(at: index, in: lines) {
            output.append(MarkdownBlankLineMarker.htmlComment)
        } else {
            output.append(line)
        }
    }

    var result = output.joined(separator: "\n")
    if hasTrailingNewline {
        result.append("\n")
    }
    return result
}

@available(iOS 26.0, macOS 26.0, *)
private func shouldConvertBlankLine(at index: Int, in lines: [String]) -> Bool {
    guard let previousIndex = previousNonEmptyLineIndex(before: index, in: lines),
          let nextIndex = nextNonEmptyLineIndex(after: index, in: lines) else {
        return false
    }

    let previous = lines[previousIndex].trimmingCharacters(in: .whitespaces)
    let next = lines[nextIndex].trimmingCharacters(in: .whitespaces)
    if previous.isEmpty || next.isEmpty {
        return false
    }

    if previous == MarkdownBlankLineMarker.htmlComment || next == MarkdownBlankLineMarker.htmlComment {
        return false
    }

    if codeFenceDelimiter(in: previous) != nil || codeFenceDelimiter(in: next) != nil {
        return false
    }

    if MarkdownLineInference.isThematicBreakLine(previous) || MarkdownLineInference.isThematicBreakLine(next) {
        return false
    }

    if MarkdownLineInference.inferListBlockKind(from: previous) != nil ||
        MarkdownLineInference.inferListBlockKind(from: next) != nil {
        return false
    }

    if previous.hasPrefix("<") || next.hasPrefix("<") {
        return false
    }

    return true
}

@available(iOS 26.0, macOS 26.0, *)
private func previousNonEmptyLineIndex(before index: Int, in lines: [String]) -> Int? {
    guard index > 0 else { return nil }
    var candidate = index - 1
    while candidate >= 0 {
        if !lines[candidate].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return candidate
        }
        if candidate == 0 { break }
        candidate -= 1
    }
    return nil
}

@available(iOS 26.0, macOS 26.0, *)
private func nextNonEmptyLineIndex(after index: Int, in lines: [String]) -> Int? {
    guard index + 1 < lines.count else { return nil }
    for candidate in (index + 1)..<lines.count
    where !lines[candidate].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return candidate
    }
    return nil
}

@available(iOS 26.0, macOS 26.0, *)
private struct CodeFence {
    let character: Character
    let length: Int
}

@available(iOS 26.0, macOS 26.0, *)
private func codeFenceDelimiter(in trimmedLine: String) -> CodeFence? {
    guard let firstCharacter = trimmedLine.first,
          firstCharacter == "`" || firstCharacter == "~" else {
        return nil
    }

    let length = trimmedLine.prefix { $0 == firstCharacter }.count
    guard length >= 3 else {
        return nil
    }

    return CodeFence(character: firstCharacter, length: length)
}
