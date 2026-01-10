import Foundation

public enum MarkdownRendering {
    public static func normalizeTaskLists(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var updated: [String] = []
        for index in lines.indices {
            let line = String(lines[index])
            if line.trimmingCharacters(in: .whitespaces).isEmpty,
               let previous = updated.last,
               isTaskListLine(previous),
               let nextLine = lines[safe: index + 1],
               isTaskListLine(String(nextLine)) {
                continue
            }

            if let match = taskItemRegex.firstMatch(
                in: line,
                range: NSRange(location: 0, length: line.utf16.count)
            ) {
                let prefixRange = match.range(at: 1)
                let contentRange = match.range(at: 2)
                if let prefix = Range(prefixRange, in: line),
                   let content = Range(contentRange, in: line) {
                    let contentText = String(line[content])
                    let trimmed = contentText.trimmingCharacters(in: .whitespaces)
                    if !(trimmed.hasPrefix("~~") && trimmed.hasSuffix("~~") && trimmed.count >= 4) {
                        updated.append("\(line[prefix])~~\(contentText)~~")
                        continue
                    }
                }
            }

            updated.append(line)
        }
        return updated.joined(separator: "\n")
    }

    private static let taskItemRegex: NSRegularExpression = {
        let pattern = #"^(\s*[-+*]\s+\[[xX]\]\s+)(.+)$"#
        return try! NSRegularExpression(pattern: pattern, options: [])
    }()

    private static let anyTaskItemRegex: NSRegularExpression = {
        let pattern = #"^\s*[-+*]\s+\[[ xX]\]\s+.+$"#
        return try! NSRegularExpression(pattern: pattern, options: [])
    }()

    private static func isTaskListLine(_ line: String) -> Bool {
        let range = NSRange(location: 0, length: line.utf16.count)
        return anyTaskItemRegex.firstMatch(in: line, range: range) != nil
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
