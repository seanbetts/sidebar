import Foundation

public enum MarkdownRendering {
    public nonisolated static func normalizeTaskLists(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var updated: [String] = []
        let taskItemRegex = makeTaskItemRegex()
        let anyTaskItemRegex = makeAnyTaskItemRegex()

        for index in lines.indices {
            let line = String(lines[index])
            if line.trimmingCharacters(in: .whitespaces).isEmpty,
               let previous = updated.last,
               isTaskListLine(previous, regex: anyTaskItemRegex),
               let nextLine = lines.indices.contains(index + 1) ? String(lines[index + 1]) : nil,
               isTaskListLine(nextLine, regex: anyTaskItemRegex) {
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

    public nonisolated static func normalizeWebsiteMarkdown(_ text: String) -> String {
        let replaced = replaceGalleryBlocks(in: text)
        return normalizeTaskLists(replaced)
    }

    private nonisolated static func makeTaskItemRegex() -> NSRegularExpression {
        let pattern = #"^(\s*[-+*]\s+\[[xX]\]\s+)(.+)$"#
        return try! NSRegularExpression(pattern: pattern, options: [])
    }

    private nonisolated static func makeAnyTaskItemRegex() -> NSRegularExpression {
        let pattern = #"^\s*[-+*]\s+\[[ xX]\]\s+.+$"#
        return try! NSRegularExpression(pattern: pattern, options: [])
    }

    private nonisolated static func isTaskListLine(_ line: String, regex: NSRegularExpression) -> Bool {
        let range = NSRange(location: 0, length: line.utf16.count)
        return regex.firstMatch(in: line, range: range) != nil
    }

    private nonisolated static func makeGalleryRegex() -> NSRegularExpression {
        let pattern = #"<figure\s+class=\"image-gallery\"[^>]*>.*?</figure>"#
        return try! NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
    }

    private nonisolated static func makeGalleryCaptionRegex() -> NSRegularExpression {
        let pattern = #"data-caption=\"([^\"]*)\""#
        return try! NSRegularExpression(pattern: pattern, options: [])
    }

    private nonisolated static func makeGalleryImageRegex() -> NSRegularExpression {
        let pattern = #"<img[^>]*\s+src=\"([^\"]+)\"[^>]*/?>"#
        return try! NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
    }

    private nonisolated static func replaceGalleryBlocks(in text: String) -> String {
        let galleryRegex = makeGalleryRegex()
        let matches = galleryRegex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
        guard !matches.isEmpty else { return text }

        var output = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: output) else { continue }
            let block = String(output[range])
            let replacement = renderGalleryMarkdown(from: block)
            output.replaceSubrange(range, with: replacement)
        }
        return output
    }

    private nonisolated static func renderGalleryMarkdown(from block: String) -> String {
        let captionRegex = makeGalleryCaptionRegex()
        let imageRegex = makeGalleryImageRegex()
        let caption = extractFirstMatch(in: block, regex: captionRegex)
        let imageUrls = imageRegex.matches(in: block, range: NSRange(location: 0, length: block.utf16.count))
            .compactMap { match -> String? in
                guard let range = Range(match.range(at: 1), in: block) else { return nil }
                return String(block[range])
            }

        var lines: [String] = imageUrls.map { url in
            "![](\(url))"
        }

        if let caption, !caption.isEmpty {
            lines.append("")
            lines.append("_\(caption)_")
        }

        return lines.joined(separator: "\n")
    }

    private nonisolated static func extractFirstMatch(in text: String, regex: NSRegularExpression) -> String? {
        let range = NSRange(location: 0, length: text.utf16.count)
        guard let match = regex.firstMatch(in: text, range: range),
              let capture = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[capture])
    }
}
