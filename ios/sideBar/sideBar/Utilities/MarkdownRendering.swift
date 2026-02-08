import Foundation
import sideBarShared

// MARK: - MarkdownRendering

public enum MarkdownRendering {
    public struct MarkdownYouTubeEmbed {
        public let sourceURL: String
        public let videoId: String
        public let embedURL: URL
    }

    public nonisolated static let imageCaptionMarker = "^caption:"

    public struct MarkdownGallery {
        public let imageUrls: [String]
        public let caption: String?

        public nonisolated init(imageUrls: [String], caption: String?) {
            self.imageUrls = imageUrls
            self.caption = caption
        }
    }

    public struct MarkdownSuppressedSVG {
        public let rawSVG: String

        public nonisolated init(rawSVG: String) {
            self.rawSVG = rawSVG
        }
    }

    public enum MarkdownContentBlock {
        case markdown(String)
        case gallery(MarkdownGallery)
        case youtube(MarkdownYouTubeEmbed)
        case suppressedSVG(MarkdownSuppressedSVG)
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
        let trimmed = content.trimmed
        guard trimmed.hasPrefix(marker) else { return content }
        let parts = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = parts.first, first.trimmed == marker else {
            return content
        }
        var endIndex: Int?
        for (index, line) in parts.enumerated().dropFirst() where line.trimmed == marker {
            endIndex = index
            break
        }
        guard let endIndex else { return content }
        let body = parts.dropFirst(endIndex + 1).joined(separator: "\n")
        return body.trimmed
    }

    public nonisolated static func normalizeMarkdownText(_ text: String) -> String {
        let normalized = normalizeTaskLists(text)
        return normalizeImageCaptions(normalized)
    }

    public nonisolated static func stripWebsiteTranscriptArtifacts(
        _ text: String
    ) -> String {
        let markerRegex = makeRegex(
            pattern: #"(?m)^\s*<!--\s*YOUTUBE_TRANSCRIPT:[^>]+-->\s*\n?"#
        )
        let legacyTitleRegex = makeRegex(
            pattern: #"(?m)^\s*###\s+Transcript of .+ video\s*\n?"#
        )
        var cleaned = markerRegex.stringByReplacingMatches(
            in: text,
            range: NSRange(location: 0, length: text.utf16.count),
            withTemplate: ""
        )
        cleaned = legacyTitleRegex.stringByReplacingMatches(
            in: cleaned,
            range: NSRange(location: 0, length: cleaned.utf16.count),
            withTemplate: ""
        )
        let extraBlankRegex = makeRegex(pattern: #"\n{3,}"#)
        return extraBlankRegex.stringByReplacingMatches(
            in: cleaned,
            range: NSRange(location: 0, length: cleaned.utf16.count),
            withTemplate: "\n\n"
        )
    }

    public nonisolated static func normalizedBlocks(from text: String) -> [MarkdownContentBlock] {
        normalizedBlocks(from: text, suppressSVG: false)
    }

    public nonisolated static func normalizedWebsiteBlocks(from text: String) -> [MarkdownContentBlock] {
        normalizedBlocks(from: text, suppressSVG: true)
    }

    private nonisolated static func normalizedBlocks(
        from text: String,
        suppressSVG: Bool
    ) -> [MarkdownContentBlock] {
        let stripped = stripFrontmatter(text)
        let blocks = splitMarkdownContent(stripped)
        var normalized: [MarkdownContentBlock] = []
        for block in blocks {
            switch block {
            case .markdown(let markdown):
                let cleanedMarkdown = normalizeMarkdownText(markdown)
                guard !cleanedMarkdown.isBlank else {
                    continue
                }
                let websiteBlocks: [MarkdownContentBlock] = suppressSVG
                    ? splitMarkdownSVGBlocks(cleanedMarkdown)
                    : [.markdown(cleanedMarkdown)]
                for websiteBlock in websiteBlocks {
                    switch websiteBlock {
                    case .markdown(let websiteMarkdown):
                        normalized.append(contentsOf: splitMarkdownEmbeds(websiteMarkdown))
                    case .suppressedSVG:
                        normalized.append(websiteBlock)
                    case .gallery, .youtube:
                        normalized.append(websiteBlock)
                    }
                }
            case .gallery, .youtube, .suppressedSVG:
                normalized.append(block)
            }
        }
        return normalized
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
        return makeRegex(pattern: pattern)
    }

    private nonisolated static func makeAnyTaskItemRegex() -> NSRegularExpression {
        let pattern = #"^\s*[-+*]\s+\[[ xX]\]\s+.+$"#
        return makeRegex(pattern: pattern)
    }

    private nonisolated static func isTaskListLine(_ line: String, regex: NSRegularExpression) -> Bool {
        let range = NSRange(location: 0, length: line.utf16.count)
        return regex.firstMatch(in: line, range: range) != nil
    }

    private nonisolated static func makeGalleryRegex() -> NSRegularExpression {
        let pattern = #"<figure\s+class=\"image-gallery\"[^>]*>.*?</figure>"#
        return makeRegex(pattern: pattern, options: [.dotMatchesLineSeparators])
    }

    private nonisolated static func makeSVGRegex() -> NSRegularExpression {
        let pattern = #"<svg\b[^>]*>.*?</svg>"#
        return makeRegex(
            pattern: pattern,
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        )
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
        return makeRegex(pattern: pattern)
    }

    private nonisolated static func makeGalleryCaptionRegex() -> NSRegularExpression {
        let pattern = #"data-caption=\"([^\"]*)\""#
        return makeRegex(pattern: pattern)
    }

    private nonisolated static func makeGalleryImageRegex() -> NSRegularExpression {
        let pattern = #"<img[^>]*\s+src=\"([^\"]+)\"[^>]*/?>"#
        return makeRegex(pattern: pattern, options: [.dotMatchesLineSeparators])
    }

    private nonisolated static func makeRegex(
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            assertionFailure("Invalid regex pattern: \(pattern). Error: \(error)")
            return fallbackRegex()
        }
    }

    private nonisolated static func fallbackRegex() -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: "$^", options: [])
        } catch {
            fatalError("Failed to create fallback regex: \(error)")
        }
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
        guard !text.isBlank else { return }
        blocks.append(.markdown(text))
    }

    private nonisolated static func splitMarkdownSVGBlocks(_ markdown: String) -> [MarkdownContentBlock] {
        let svgRegex = makeSVGRegex()
        let matches = svgRegex.matches(
            in: markdown,
            range: NSRange(location: 0, length: markdown.utf16.count)
        )
        guard !matches.isEmpty else {
            return [.markdown(markdown)]
        }

        var blocks: [MarkdownContentBlock] = []
        var currentIndex = markdown.startIndex
        for match in matches {
            guard let range = Range(match.range, in: markdown) else { continue }
            let before = String(markdown[currentIndex..<range.lowerBound])
            appendMarkdownIfNeeded(before, to: &blocks)
            let rawSVG = String(markdown[range])
            blocks.append(.suppressedSVG(MarkdownSuppressedSVG(rawSVG: rawSVG)))
            currentIndex = range.upperBound
        }

        let trailing = String(markdown[currentIndex...])
        appendMarkdownIfNeeded(trailing, to: &blocks)
        return blocks
    }

    private nonisolated static func splitMarkdownEmbeds(_ markdown: String) -> [MarkdownContentBlock] {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard !lines.isEmpty else { return [] }

        var blocks: [MarkdownContentBlock] = []
        var buffer: [String] = []

        func flushBuffer() {
            let text = buffer.joined(separator: "\n")
            appendMarkdownIfNeeded(text, to: &blocks)
            buffer.removeAll(keepingCapacity: true)
        }

        for line in lines {
            if let embed = youTubeEmbed(from: line) {
                flushBuffer()
                blocks.append(.youtube(embed))
            } else {
                buffer.append(line)
            }
        }
        flushBuffer()
        return blocks
    }

    private nonisolated static func youTubeEmbed(from line: String) -> MarkdownYouTubeEmbed? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let sourceURL: String?
        if let match = firstCapture(
            pattern: #"^\[YouTube\]\(([^)]+)\)$"#,
            in: trimmed,
            options: [.caseInsensitive]
        ) {
            sourceURL = match
        } else if firstCapture(pattern: #"^(https?://\S+)$"#, in: trimmed) != nil {
            sourceURL = trimmed
        } else {
            sourceURL = nil
        }

        guard let sourceURL else { return nil }
        guard let videoId = YouTubeURLPolicy.extractVideoId(from: sourceURL),
              let embedURL = YouTubeURLPolicy.embedURL(videoId: videoId) else {
            return nil
        }
        return MarkdownYouTubeEmbed(sourceURL: sourceURL, videoId: videoId, embedURL: embedURL)
    }

    private nonisolated static func firstCapture(
        pattern: String,
        in text: String,
        options: NSRegularExpression.Options = []
    ) -> String? {
        let regex = makeRegex(pattern: pattern, options: options)
        let range = NSRange(location: 0, length: text.utf16.count)
        guard let match = regex.firstMatch(in: text, range: range),
              let capture = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[capture])
    }
}
