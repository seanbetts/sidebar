import Foundation
import sideBarShared

extension MarkdownRendering {
    public nonisolated static func plainTextForWebsiteShare(_ content: String) -> String {
        let stripped = stripFrontmatter(content)
        let cleaned = stripWebsiteTranscriptArtifacts(stripped)
        guard !cleaned.isBlank else { return "" }

        let blocks = normalizedWebsiteBlocks(from: cleaned)
        var textBlocks: [String] = []
        textBlocks.reserveCapacity(blocks.count)

        for block in blocks {
            switch block {
            case .markdown(let markdown):
                let plainText = plainTextFromMarkdown(markdown)
                guard !plainText.isBlank else { continue }
                textBlocks.append(plainText)
            case .gallery(let gallery):
                guard let caption = gallery.caption?.trimmed, !caption.isEmpty else { continue }
                textBlocks.append(caption)
            case .youtube(let embed):
                textBlocks.append(embed.sourceURL)
            case .suppressedSVG:
                continue
            }
        }

        return normalizeWebsiteShareWhitespace(textBlocks.joined(separator: "\n\n"))
    }

    private nonisolated static func plainTextFromMarkdown(_ markdown: String) -> String {
        do {
            let attributed = try AttributedString(
                markdown: markdown,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .full,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            )
            return String(attributed.characters)
        } catch {
            return markdown
        }
    }

    private nonisolated static func normalizeWebsiteShareWhitespace(_ text: String) -> String {
        var normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let trailingWhitespaceRegex = makeRegex(pattern: #"(?m)[ \t]+$"#)
        normalized = trailingWhitespaceRegex.stringByReplacingMatches(
            in: normalized,
            range: NSRange(location: 0, length: normalized.utf16.count),
            withTemplate: ""
        )
        let extraBlankRegex = makeRegex(pattern: #"\n{3,}"#)
        normalized = extraBlankRegex.stringByReplacingMatches(
            in: normalized,
            range: NSRange(location: 0, length: normalized.utf16.count),
            withTemplate: "\n\n"
        )
        return normalized.trimmed
    }
}
