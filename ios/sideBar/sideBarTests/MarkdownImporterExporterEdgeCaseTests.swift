import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class MarkdownImporterExporterEdgeCaseTests: XCTestCase {
    func testExporterPreservesConsecutiveAndTrailingBlankLines() {
        let attributed = AttributedString("Line 1\n\n\nLine 2\n")
        let exporter = MarkdownExporter()
        let exported = exporter.markdown(from: attributed)

        XCTAssertEqual(
            exported,
            """
            Line 1
            <!-- sidebar-blank-line -->
            <!-- sidebar-blank-line -->
            Line 2
            <!-- sidebar-blank-line -->
            """
        )
    }

    func testBlankLineMarkerRoundTripPreservesEditorBlankLines() {
        let markdown = """
        Line 1
        <!-- sidebar-blank-line -->
        Line 2
        """
        let importer = MarkdownImporter()
        let exporter = MarkdownExporter()

        let imported = importer.attributedString(from: markdown).attributedString
        XCTAssertEqual(String(imported.characters), "Line 1\n\nLine 2")

        let exported = exporter.markdown(from: imported)
        XCTAssertEqual(exported, markdown)
    }

    func testMixedListAndTaskRoundTripIsStable() {
        let markdown = """
        > - [ ] Open task
        > - [x] Done task

        - Parent
          - Child
        - Sibling
        """
        let importer = MarkdownImporter()
        let exporter = MarkdownExporter()

        let imported = importer.attributedString(from: markdown)
        let canonical = exporter.markdown(from: imported.attributedString, frontmatter: imported.frontmatter)
        let reimported = importer.attributedString(from: canonical)
        let canonicalAgain = exporter.markdown(from: reimported.attributedString, frontmatter: reimported.frontmatter)

        XCTAssertEqual(canonicalAgain, canonical)
        XCTAssertTrue(canonical.contains("> - [ ] Open task"), canonical)
        XCTAssertTrue(canonical.contains("> - [x]"), canonical)
        XCTAssertTrue(canonical.contains("- Parent"), canonical)
        XCTAssertTrue(canonical.contains("  - Child"), canonical)
    }
}
