import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class MarkdownImporterExporterRegressionTests: XCTestCase {
    func testSoftBreakRoundTripDoesNotForceHardBreak() {
        let markdown = """
        first line
        second line
        """
        let importer = MarkdownImporter()
        let exporter = MarkdownExporter()

        let imported = importer.attributedString(from: markdown).attributedString
        XCTAssertEqual(String(imported.characters), "first line second line")

        let exported = exporter.markdown(from: imported)
        XCTAssertEqual(exported, "first line second line")
    }

    func testListKindTransitionWithSharedIdentityInsertsBlankLine() {
        var attributed = AttributedString("Bullet\nOrdered")
        let ranges = lineRanges(in: attributed)
        XCTAssertEqual(ranges.count, 2)

        attributed[ranges[0]].blockKind = .bulletList
        attributed[ranges[0]].listDepth = 1
        attributed[ranges[1]].blockKind = .orderedList
        attributed[ranges[1]].listDepth = 1

        let unorderedIntent = PresentationIntent(.unorderedList, identity: 1)
        let unorderedItem = PresentationIntent(.listItem(ordinal: 1), identity: 1001, parent: unorderedIntent)
        attributed[ranges[0]][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
            .paragraph,
            identity: 1,
            parent: unorderedItem
        )

        let orderedIntent = PresentationIntent(.orderedList, identity: 1)
        let orderedItem = PresentationIntent(.listItem(ordinal: 1), identity: 1001, parent: orderedIntent)
        attributed[ranges[1]][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
            .paragraph,
            identity: 1,
            parent: orderedItem
        )

        let exported = MarkdownExporter().markdown(from: attributed)
        XCTAssertEqual(exported, "- Bullet\n\n1. Ordered", exported)
    }

    func testCanonicalImportExportIsIdempotentForRepresentativeDocuments() {
        let cases: [String] = [
            """
            # Title

            Paragraph with **bold** and *italic* and `code`.
            """,
            """
            - Parent
              - Child
            - Sibling
            """,
            """
            > 1. Numbered
            > 2. Numbered
            >
            > - [ ] Task
            > - [x] Done
            """,
            """
            | Name | Count |
            | --- | ---: |
            | Alpha | 1 |
            """,
            """
            ```swift
            let a = 1
            print(a)
            ```
            """,
            """
            Line 1
            <!-- sidebar-blank-line -->
            Line 2
            """
        ]

        let importer = MarkdownImporter()
        let exporter = MarkdownExporter()

        for (index, markdown) in cases.enumerated() {
            let firstImport = importer.attributedString(from: markdown)
            let canonical = exporter.markdown(
                from: firstImport.attributedString,
                frontmatter: firstImport.frontmatter
            )
            let secondImport = importer.attributedString(from: canonical)
            let canonicalAgain = exporter.markdown(
                from: secondImport.attributedString,
                frontmatter: secondImport.frontmatter
            )
            XCTAssertEqual(canonicalAgain, canonical, "Idempotency failed for case \\(index)")
        }
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
