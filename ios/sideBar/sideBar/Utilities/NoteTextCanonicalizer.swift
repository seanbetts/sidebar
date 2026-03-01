@preconcurrency import Foundation

/// Canonicalization entrypoint for notes text payloads used by offline notes flows.
public enum NoteTextCanonicalizer {
    public static func canonicalized(_ content: String) -> String {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            return content
        }
        return canonicalizedForLatestAttributedText(content)
    }

    @available(iOS 26.0, macOS 26.0, *)
    private static func canonicalizedForLatestAttributedText(_ content: String) -> String {
        let imported = MarkdownImporter().attributedString(from: content)
        let constrained = MarkdownFormattingDefinition().constrainedDocument(imported.attributedString)
        return MarkdownExporter().markdown(from: constrained, frontmatter: imported.frontmatter)
    }
}
