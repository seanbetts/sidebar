import Foundation

public enum MarkdownRendering {
    public nonisolated static let imageCaptionMarker = "^caption:"

    public struct MarkdownGallery {
        public let imageUrls: [String]
        public let caption: String?

        public nonisolated init(imageUrls: [String], caption: String?) {
            self.imageUrls = imageUrls
            self.caption = caption
        }
    }

    public enum MarkdownContentBlock {
        case markdown(String)
        case gallery(MarkdownGallery)
    }

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

    public nonisolated static func stripFrontmatter(_ content: String) -> String {
        let marker = "---"
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(marker) else { return content }
        let parts = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = parts.first, first.trimmingCharacters(in: .whitespacesAndNewlines) == marker else {
            return content
        }
        var endIndex: Int? = nil
        for (index, line) in parts.enumerated().dropFirst() {
            if line.trimmingCharacters(in: .whitespacesAndNewlines) == marker {
                endIndex = index
                break
            }
        }
        guard let endIndex else { return content }
        let body = parts.dropFirst(endIndex + 1).joined(separator: "\n")
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public nonisolated static func normalizeMarkdownText(_ text: String) -> String {
        let normalized = normalizeTaskLists(text)
        return normalizeImageCaptions(normalized)
    }

    public nonisolated static func normalizedBlocks(from text: String) -> [MarkdownContentBlock] {
        let stripped = stripFrontmatter(text)
        let blocks = splitMarkdownContent(stripped)
        return blocks.compactMap { block in
            switch block {
            case .markdown(let markdown):
                let normalized = normalizeMarkdownText(markdown)
                guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }
                return .markdown(normalized)
            case .gallery:
                return block
            }
        }
    }

    public nonisolated static func splitMarkdownContent(_ text: String) -> [MarkdownContentBlock] {
        let galleryRegex = makeGalleryRegex()
        let matches = galleryRegex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
        guard !matches.isEmpty else {
            return [.markdown(text)]
        }

        var blocks: [MarkdownContentBlock] = []
        var currentIndex = text.startIndex

        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            let before = String(text[currentIndex..<range.lowerBound])
            appendMarkdownIfNeeded(before, to: &blocks)

            let block = String(text[range])
            if let gallery = parseGalleryBlock(block) {
                blocks.append(.gallery(gallery))
            } else {
                appendMarkdownIfNeeded(block, to: &blocks)
            }

            currentIndex = range.upperBound
        }

        let trailing = String(text[currentIndex...])
        appendMarkdownIfNeeded(trailing, to: &blocks)

        return blocks
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

    private nonisolated static func normalizeImageCaptions(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var updated: [String] = []
        let regex = makeImageCaptionRegex()

        for lineSlice in lines {
            let line = String(lineSlice)
            let range = NSRange(location: 0, length: line.utf16.count)
            if let match = regex.firstMatch(in: line, range: range) {
                let imageRange = match.range(at: 1)
                let captionRange = match.range(at: 3)
                if let image = Range(imageRange, in: line),
                   let caption = Range(captionRange, in: line) {
                    updated.append(String(line[image]))
                    updated.append("")
                    let captionText = String(line[caption]).trimmingCharacters(in: .whitespaces)
                    updated.append("\(imageCaptionMarker) \(captionText)")
                    continue
                }
            }
            updated.append(line)
        }
        return updated.joined(separator: "\n")
    }

    private nonisolated static func makeImageCaptionRegex() -> NSRegularExpression {
        let pattern = #"^\s*(!\[[^\]]*\]\([^)]+\))\s*([*_])(.+?)\2\s*$"#
        return try! NSRegularExpression(pattern: pattern, options: [])
    }

    private nonisolated static func makeGalleryCaptionRegex() -> NSRegularExpression {
        let pattern = #"data-caption=\"([^\"]*)\""#
        return try! NSRegularExpression(pattern: pattern, options: [])
    }

    private nonisolated static func makeGalleryImageRegex() -> NSRegularExpression {
        let pattern = #"<img[^>]*\s+src=\"([^\"]+)\"[^>]*/?>"#
        return try! NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
    }

    private nonisolated static func parseGalleryBlock(_ block: String) -> MarkdownGallery? {
        let captionRegex = makeGalleryCaptionRegex()
        let imageRegex = makeGalleryImageRegex()
        let caption = extractFirstMatch(in: block, regex: captionRegex)
        let imageUrls = extractImageUrls(in: block, regex: imageRegex)
        guard !imageUrls.isEmpty else { return nil }
        return MarkdownGallery(imageUrls: imageUrls, caption: caption)
    }

    private nonisolated static func extractFirstMatch(in text: String, regex: NSRegularExpression) -> String? {
        let range = NSRange(location: 0, length: text.utf16.count)
        guard let match = regex.firstMatch(in: text, range: range),
              let capture = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[capture])
    }

    private nonisolated static func extractImageUrls(in text: String, regex: NSRegularExpression) -> [String] {
        regex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
            .compactMap { match -> String? in
                guard let range = Range(match.range(at: 1), in: text) else { return nil }
                return String(text[range])
            }
    }

    private nonisolated static func appendMarkdownIfNeeded(_ text: String, to blocks: inout [MarkdownContentBlock]) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        blocks.append(.markdown(text))
    }
}
