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

    public func attributedString(from markdown: String) -> MarkdownImportResult {
        let split = splitFrontmatter(from: markdown)
        let document = Document(parsing: split.body)
        var walker = MarkdownToAttributedStringWalker(style: style)
        walker.visit(document)
        return MarkdownImportResult(attributedString: walker.result, frontmatter: split.frontmatter)
    }
}
