@preconcurrency import Foundation
import Markdown
import sideBarShared
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
public struct NoteTextImportResult {
    public let attributedString: AttributedString
    public let frontmatter: String?

    public init(attributedString: AttributedString, frontmatter: String?) {
        self.attributedString = attributedString
        self.frontmatter = frontmatter
    }
}

@available(iOS 26.0, macOS 26.0, *)
public struct NoteTextImporter {
    private let style: NoteTextStyle

    public init() {
        self.style = .default
    }

    public func attributedString(
        from content: String,
        baseFontSize: CGFloat = 16
    ) -> NoteTextImportResult {
        let split = noteTextSplitFrontmatter(from: content)
        let preprocessedBody = noteTextPreserveAuthorBlankLines(in: split.body)
        let document = Document(parsing: preprocessedBody)
        var walker = NoteTextToAttributedStringWalker(
            style: style,
            baseFontSize: baseFontSize
        )
        walker.visit(document)
        return NoteTextImportResult(attributedString: walker.result, frontmatter: split.frontmatter)
    }
}

@available(iOS 26.0, macOS 26.0, *)
private func noteTextSplitFrontmatter(from content: String) -> (frontmatter: String?, body: String) {
    let trimmed = content.trimmed
    let marker = "---"
    guard trimmed.hasPrefix(marker) else {
        return (nil, content)
    }

    let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
    guard let first = lines.first, first.trimmed == marker else {
        return (nil, content)
    }

    var endIndex: Int?
    for (index, line) in lines.enumerated().dropFirst() where line.trimmed == marker {
        endIndex = index
        break
    }

    guard let endIndex else {
        return (nil, content)
    }

    let frontmatterLines = lines[0...endIndex].joined(separator: "\n")
    let bodyLines = lines.dropFirst(endIndex + 1).joined(separator: "\n")
    return (frontmatterLines, bodyLines)
}
