import Foundation
import sideBarShared

extension MarkdownRendering {
    nonisolated static func youTubeEmbed(from line: String) -> MarkdownYouTubeEmbed? {
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

    nonisolated static func firstCapture(
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
