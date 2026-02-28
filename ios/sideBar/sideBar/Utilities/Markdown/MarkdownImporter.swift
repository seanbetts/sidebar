@preconcurrency import Foundation
import Markdown
import sideBarShared
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
public struct MarkdownImportResult {
    public let attributedString: AttributedString
    public let frontmatter: String?

    public init(attributedString: AttributedString, frontmatter: String?) {
        self.attributedString = attributedString
        self.frontmatter = frontmatter
    }
}

@available(iOS 26.0, macOS 26.0, *)
public struct MarkdownImporter {
    private let style: SideBarMarkdownStyle

    public init() {
        self.style = .default
    }

    public func attributedString(
        from markdown: String,
        baseFontSize: CGFloat = 16
    ) -> MarkdownImportResult {
        let split = splitFrontmatter(from: markdown)
        let preprocessedBody = preserveAuthorBlankLines(in: split.body)
        let document = Document(parsing: preprocessedBody)
        var walker = MarkdownToAttributedStringWalker(
            style: style,
            baseFontSize: baseFontSize
        )
        walker.visit(document)
        return MarkdownImportResult(attributedString: walker.result, frontmatter: split.frontmatter)
    }
}

@available(iOS 26.0, macOS 26.0, *)
func splitFrontmatter(from markdown: String) -> (frontmatter: String?, body: String) {
    let trimmed = markdown.trimmed
    let marker = "---"
    guard trimmed.hasPrefix(marker) else {
        return (nil, markdown)
    }

    let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
    guard let first = lines.first, first.trimmed == marker else {
        return (nil, markdown)
    }

    var endIndex: Int?
    for (index, line) in lines.enumerated().dropFirst() where line.trimmed == marker {
        endIndex = index
        break
    }

    guard let endIndex else {
        return (nil, markdown)
    }

    let frontmatterLines = lines[0...endIndex].joined(separator: "\n")
    let bodyLines = lines.dropFirst(endIndex + 1).joined(separator: "\n")
    return (frontmatterLines, bodyLines)
}

public enum MarkdownCanonicalizer {
    public static func canonicalized(_ markdown: String) -> String {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            return markdown
        }
        return canonicalizedForLatestAttributedMarkdown(markdown)
    }

    @available(iOS 26.0, macOS 26.0, *)
    private static func canonicalizedForLatestAttributedMarkdown(_ markdown: String) -> String {
        let imported = MarkdownImporter().attributedString(from: markdown)
        let constrained = MarkdownFormattingDefinition().constrainedDocument(imported.attributedString)
        return MarkdownExporter().markdown(from: constrained, frontmatter: imported.frontmatter)
    }
}
