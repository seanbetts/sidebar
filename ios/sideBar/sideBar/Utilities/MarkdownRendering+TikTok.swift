import Foundation
import sideBarShared

extension MarkdownRendering {
    nonisolated static func trailingMarkdownImageURL(in buffer: [String]) -> String? {
        var index = buffer.count - 1
        while index >= 0 {
            let line = buffer[index]
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                index -= 1
                continue
            }
            return markdownImageURL(from: line)
        }
        return nil
    }

    nonisolated static func discardTrailingMarkdownImage(from buffer: inout [String], expectedURL: String) {
        while let last = buffer.last, last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            buffer.removeLast()
        }
        if let last = buffer.last,
           markdownImageURL(from: last) == expectedURL {
            buffer.removeLast()
        }
        while let last = buffer.last, last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            buffer.removeLast()
        }
    }

    nonisolated static func consumeTrailingTikTokFallbackLines(
        from lines: [String],
        startingAfter markerIndex: Int,
        sourceURL: String
    ) -> Int {
        var index = markerIndex + 1
        while index < lines.count, lines[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            index += 1
        }
        if index < lines.count, isTikTokOpenLink(lines[index], sourceURL: sourceURL) {
            index += 1
            while index < lines.count, lines[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                index += 1
            }
        }
        return index
    }

    nonisolated static func tikTokEmbed(from line: String) -> MarkdownTikTokEmbed? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let payload = firstCapture(
            pattern: #"^<!--\s*TIKTOK_EMBED:\s*(\{.+\})\s*-->$"#,
            in: trimmed
        ) else {
            return nil
        }

        guard let data = payload.data(using: String.Encoding.utf8),
              let rawObject = try? JSONSerialization.jsonObject(with: data),
              let object = rawObject as? [String: Any] else {
            return nil
        }

        guard let sourceURL = object["source_url"] as? String,
              let videoId = object["video_id"] as? String,
              let title = object["title"] as? String,
              let thumbnailURL = object["thumbnail_url"] as? String,
              !sourceURL.isEmpty,
              !videoId.isEmpty,
              !title.isEmpty,
              !thumbnailURL.isEmpty else {
            return nil
        }

        return MarkdownTikTokEmbed(
            sourceURL: sourceURL,
            videoId: videoId,
            authorName: object["author_name"] as? String,
            authorURL: object["author_url"] as? String,
            title: title,
            thumbnailURL: thumbnailURL
        )
    }

    private nonisolated static func markdownImageURL(from line: String) -> String? {
        firstCapture(
            pattern: #"^!\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)$"#,
            in: line.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private nonisolated static func isTikTokOpenLink(_ line: String, sourceURL: String) -> Bool {
        guard let linkURL = firstCapture(
            pattern: #"^\[Open on TikTok\]\(([^)]+)\)$"#,
            in: line.trimmingCharacters(in: .whitespacesAndNewlines),
            options: [NSRegularExpression.Options.caseInsensitive]
        ) else {
            return false
        }
        return linkURL == sourceURL
    }
}
