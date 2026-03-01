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
        XCTAssertEqual(exported, "Line 1\n\nLine 2")
    }

    func testExporterUsesPlainBlankLineBetweenParagraphs() {
        let attributed = AttributedString("Line 1\n\nLine 2")
        let exported = MarkdownExporter().markdown(from: attributed)

        XCTAssertEqual(exported, "Line 1\n\nLine 2")
    }

    func testImporterTreatsSingleBlankLineAsParagraphSeparator() {
        let markdown = """
        Alpha

        Beta
        """
        let importer = MarkdownImporter()
        let exporter = MarkdownExporter()

        let imported = importer.attributedString(from: markdown).attributedString
        XCTAssertEqual(String(imported.characters), "Alpha\nBeta")

        let exported = exporter.markdown(from: imported)
        XCTAssertEqual(exported, markdown)
    }

    func testEditorBlankLineRoundTripUsesExplicitMarker() {
        var attributed = AttributedString("Alpha\n\nBeta")
        let lines = lineRanges(in: attributed)
        XCTAssertEqual(lines.count, 3)
        let blankLineRange = lines[1]
        let newlineRange = blankLineRange.lowerBound..<lines[2].lowerBound
        attributed[newlineRange].blockKind = .blankLine

        let exported = MarkdownExporter().markdown(from: attributed)
        XCTAssertEqual(exported, "Alpha\n\(MarkdownBlankLineMarker.htmlComment)\nBeta")

        let reimported = MarkdownImporter().attributedString(from: exported).attributedString
        XCTAssertEqual(String(reimported.characters), "Alpha\n\nBeta")
    }

    func testImporterDoesNotConvertBlankLinesInsideFencedCodeToBlankLineMarkers() {
        let markdown = """
        ```swift
        let a = 1

        let b = 2
        ```
        """
        let imported = MarkdownImporter().attributedString(from: markdown).attributedString
        let exported = MarkdownExporter().markdown(from: imported)

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

    private func lineRanges(in text: AttributedString) -> [Range<AttributedString.Index>] {
        var ranges: [Range<AttributedString.Index>] = []
        var lineStart = text.startIndex
        var current = text.startIndex

        while current < text.endIndex {
            if text.characters[current].isNewline {
                ranges.append(lineStart..<current)
                lineStart = text.index(afterCharacter: current)
                current = lineStart
            } else {
                current = text.index(afterCharacter: current)
            }
        }

        if lineStart <= text.endIndex {
            ranges.append(lineStart..<text.endIndex)
        }
        return ranges
    }
}
