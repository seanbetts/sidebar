@preconcurrency import Foundation

/// Canonicalization entrypoint for notes text payloads used by offline notes flows.
public enum NoteTextCanonicalizer {
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
