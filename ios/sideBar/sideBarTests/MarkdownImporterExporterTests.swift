import XCTest
import sideBarShared
@testable import sideBar

@available(iOS 26.0, macOS 26.0, *)

@MainActor
final class MarkdownImporterExporterTests: XCTestCase {
    func testImportExtractsFrontmatter() {
        let markdown = "---\ntitle: Test\n---\nHello"
        let result = MarkdownImporter().attributedString(from: markdown)

        XCTAssertEqual(result.frontmatter, "---\ntitle: Test\n---")
        XCTAssertEqual(String(result.attributedString.characters).trimmed, "Hello")
    }

    func testImageCaptionExportsMarker() {
        var text = AttributedString("Caption")
        let range = text.startIndex..<text.endIndex
        text[range].blockKind = .imageCaption

        let markdown = MarkdownExporter().markdown(from: text)
        XCTAssertEqual(markdown, "^caption: Caption")
    }

    func testGalleryBlockExportsRawHTML() {
        let html = "<figure class=\"image-gallery\"><img src=\"https://example.com/a.png\" /></figure>"
        var text = AttributedString(html)
        let range = text.startIndex..<text.endIndex
        text[range].blockKind = .gallery

        let markdown = MarkdownExporter().markdown(from: text)
        XCTAssertEqual(markdown, html)
    }

    func testInlineStylesRoundTrip() {
        let markdown = "**bold** *italic* `code` ~~strike~~ [Link](https://example.com)"
        let result = MarkdownImporter().attributedString(from: markdown)
        let exported = MarkdownExporter().markdown(from: result.attributedString)

        XCTAssertTrue(exported.contains("**bold**"))
        XCTAssertTrue(exported.contains("*italic*"))
        XCTAssertTrue(exported.contains("`code`"))
        XCTAssertTrue(exported.contains("~~strike~~"))
        XCTAssertTrue(exported.contains("[Link](https://example.com)"))
    }

    func testInlineMarkersPreservedInImport() {
        let markdown = "**bold** *italic* `code` ~~strike~~"
        let result = MarkdownImporter().attributedString(from: markdown)
        let text = String(result.attributedString.characters)

        XCTAssertTrue(text.contains("**bold**"))
        XCTAssertTrue(text.contains("*italic*"))
        XCTAssertTrue(text.contains("`code`"))
        XCTAssertTrue(text.contains("~~strike~~"))
    }

    func testInlineMarkersDoNotDoubleOnExport() {
        let markdown = "**bold** *italic* `code` ~~strike~~"
        let result = MarkdownImporter().attributedString(from: markdown)
        let exported = MarkdownExporter().markdown(from: result.attributedString)

        XCTAssertTrue(exported.contains("**bold**"))
        XCTAssertTrue(exported.contains("*italic*"))
        XCTAssertTrue(exported.contains("`code`"))
        XCTAssertTrue(exported.contains("~~strike~~"))
        XCTAssertFalse(exported.contains("****"))
        XCTAssertFalse(exported.contains("````"))
    }

    func testInlineExportKeepsFormattingWhenLineContainsLiteralMarkerText() {
        var text = AttributedString("literal *asterisks* and bold")
        guard let boldRange = text.range(of: "bold") else {
            XCTFail("Expected test content")
            return
        }
        text[boldRange].inlinePresentationIntent = [.stronglyEmphasized]

        let exported = MarkdownExporter().markdown(from: text)

        XCTAssertTrue(exported.contains("*asterisks*"), exported)
        XCTAssertTrue(exported.contains("**bold**"), exported)
    }

    func testNestedListPreservesIndentation() {
        let markdown = """
        - Item 1
          - Item 1.1
        """
        let result = MarkdownImporter().attributedString(from: markdown)
        let exported = MarkdownExporter().markdown(from: result.attributedString)

        XCTAssertTrue(exported.contains("- Item 1"))
        XCTAssertTrue(exported.contains("  - Item 1.1"))
    }

    func testBlockTypesRoundTrip() {
        let markdown = """
        # Heading

        > Quote

        - Item

        1. Ordered

        - [x] Done

        ```
        code
        ```

        ---
        """
        let result = MarkdownImporter().attributedString(from: markdown)
        let exported = MarkdownExporter().markdown(from: result.attributedString)

        XCTAssertTrue(exported.contains("Heading"), exported)
        XCTAssertTrue(exported.contains("Quote"), exported)
        XCTAssertTrue(exported.contains("Item"), exported)
        XCTAssertTrue(exported.contains("Ordered"), exported)
        XCTAssertTrue(exported.contains("Done"), exported)
        XCTAssertTrue(exported.contains("code"), exported)
        XCTAssertTrue(exported.contains("---"))
    }

    func testRoundTripPreservesText() {
        let markdown = """
        # Title

        Paragraph with **bold** and *italic*.
        """
        let importer = MarkdownImporter()
        let exporter = MarkdownExporter()

        let first = importer.attributedString(from: markdown).attributedString
        let roundTrip = importer.attributedString(from: exporter.markdown(from: first)).attributedString

        XCTAssertEqual(String(first.characters), String(roundTrip.characters))
    }

    func testTableRoundTrip() {
        let markdown = """
        | Name | Count |
        | --- | ---: |
        | Alpha | 1 |
        """
        let importer = MarkdownImporter()
        let exporter = MarkdownExporter()

        let first = importer.attributedString(from: markdown).attributedString
        let exported = exporter.markdown(from: first)

        XCTAssertTrue(exported.contains("| Name | Count |"))
        XCTAssertTrue(exported.contains("| --- | ---: |"))
        XCTAssertTrue(exported.contains("| Alpha | 1 |"))
    }

    func testBlockquoteBulletListRoundTripPreservesPrefixOrder() {
        let markdown = """
        > - Item 1
        > - Item 2
        """
        let importer = MarkdownImporter()
        let exporter = MarkdownExporter()

        let first = importer.attributedString(from: markdown).attributedString
        let exported = exporter.markdown(from: first)

        XCTAssertTrue(exported.contains("> - Item 1"), exported)
        XCTAssertTrue(exported.contains("> - Item 2"), exported)
        XCTAssertFalse(exported.contains("- > -"), exported)
    }

    func testBlockquoteOrderedListRoundTripPreservesPrefixOrder() {
        let markdown = """
        > 1. One
        > 2. Two
        """
        let importer = MarkdownImporter()
        let exporter = MarkdownExporter()

        let first = importer.attributedString(from: markdown).attributedString
        let exported = exporter.markdown(from: first)

        XCTAssertTrue(exported.contains("> 1. One"), exported)
        XCTAssertTrue(exported.contains("> 2. Two"), exported)
        XCTAssertFalse(exported.contains("1. >"), exported)
    }
}
