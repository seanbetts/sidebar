import XCTest
@testable import sideBar

@available(iOS 26.0, macOS 26.0, *)
final class MarkdownImporterExporterTests: XCTestCase {
    func testImportExtractsFrontmatter() {
        let markdown = "---\ntitle: Test\n---\nHello"
        let result = MarkdownImporter().attributedString(from: markdown)

        XCTAssertEqual(result.frontmatter, "---\ntitle: Test\n---")
        XCTAssertEqual(String(result.attributedString.characters).trimmed, "Hello")
    }

    func testImageCaptionExportsMarker() {
        var text = AttributedString("Caption")
        text.blockKind = .imageCaption

        let markdown = MarkdownExporter().markdown(from: text)
        XCTAssertEqual(markdown, "^caption: Caption")
    }

    func testGalleryBlockExportsRawHTML() {
        let html = "<figure class=\"image-gallery\"><img src=\"https://example.com/a.png\" /></figure>"
        var text = AttributedString(html)
        text.blockKind = .gallery

        let markdown = MarkdownExporter().markdown(from: text)
        XCTAssertEqual(markdown, html)
    }
}
