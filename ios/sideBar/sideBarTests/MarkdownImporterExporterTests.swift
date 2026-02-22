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

    func testImportInlineStylesOmitLiteralMarkdownMarkersInAttributedText() {
        let markdown = "**bold** *italic* `code` ~~strike~~"
        let result = MarkdownImporter().attributedString(from: markdown)
        let text = String(result.attributedString.characters)

        XCTAssertEqual(text, "bold italic code strike")
        XCTAssertFalse(text.contains("**"))
        XCTAssertFalse(text.contains("*"))
        XCTAssertFalse(text.contains("`"))
        XCTAssertFalse(text.contains("~~"))
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

    func testInlineExportEscapesLiteralMarkersAndSerializesSemanticStyles() {
        var attributed = AttributedString("literal **stars** and styled")
        guard let styledRange = attributed.range(of: "styled") else {
            XCTFail("Expected styled range")
            return
        }
        attributed[styledRange].inlinePresentationIntent = [.stronglyEmphasized]

        let exported = MarkdownExporter().markdown(from: attributed)

        XCTAssertEqual(exported, #"literal \*\*stars\*\* and **styled**"#)
    }

    func testInlineExportPreservesLinkWithInlineStyleSemantics() {
        var attributed = AttributedString("Link")
        let range = attributed.startIndex..<attributed.endIndex
        attributed[range].inlinePresentationIntent = [.stronglyEmphasized]
        attributed[range].link = URL(string: "https://example.com")

        let exported = MarkdownExporter().markdown(from: attributed)

        XCTAssertEqual(exported, "[**Link**](https://example.com)")
    }

    func testInlineCodeUsesSafeFenceLengthWhenTextContainsBackticks() {
        var attributed = AttributedString("value`tick")
        let range = attributed.startIndex..<attributed.endIndex
        attributed[range].inlinePresentationIntent = [.code]

        let exported = MarkdownExporter().markdown(from: attributed)

        XCTAssertEqual(exported, "``value`tick``")
    }

    func testImportHeadingOmitsLiteralHeadingMarkersInAttributedText() {
        let markdown = "# Title"
        let result = MarkdownImporter().attributedString(from: markdown)
        let text = String(result.attributedString.characters)

        XCTAssertEqual(text, "Title")
        XCTAssertFalse(text.contains("#"))
    }

    func testImportListAndBlockquoteOmitLiteralMarkdownMarkersInAttributedText() {
        let markdown = """
        > - Bullet
        > 1. Ordered
        > - [ ] Task
        """
        let result = MarkdownImporter().attributedString(from: markdown)
        let text = String(result.attributedString.characters)

        XCTAssertEqual(text, "Bullet\nOrdered\nTask")
        XCTAssertFalse(text.contains(">"))
        XCTAssertFalse(text.contains("- "))
        XCTAssertFalse(text.contains("[ ]"))
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

    func testNestedOrderedListPreservesParentOrdinalProgression() {
        var attributed = AttributedString("Parent 1\nChild 1.1\nParent 2")
        let ranges = lineRanges(in: attributed)
        XCTAssertEqual(ranges.count, 3)

        attributed[ranges[0]].blockKind = .orderedList
        attributed[ranges[0]].listDepth = 1
        attributed[ranges[1]].blockKind = .orderedList
        attributed[ranges[1]].listDepth = 2
        attributed[ranges[2]].blockKind = .orderedList
        attributed[ranges[2]].listDepth = 1

        let exported = MarkdownExporter().markdown(from: attributed)

        XCTAssertTrue(exported.contains("1. Parent 1"), exported)
        XCTAssertTrue(exported.contains("  1. Child 1.1"), exported)
        XCTAssertTrue(exported.contains("2. Parent 2"), exported)
        XCTAssertFalse(exported.contains("1. Parent 2"), exported)
    }

    func testNestedBulletUnderOrderedParentDoesNotResetParentOrdinal() {
        var attributed = AttributedString("Parent 1\nChild bullet\nParent 2")
        let ranges = lineRanges(in: attributed)
        XCTAssertEqual(ranges.count, 3)

        attributed[ranges[0]].blockKind = .orderedList
        attributed[ranges[0]].listDepth = 1
        attributed[ranges[1]].blockKind = .bulletList
        attributed[ranges[1]].listDepth = 2
        attributed[ranges[2]].blockKind = .orderedList
        attributed[ranges[2]].listDepth = 1

        let exported = MarkdownExporter().markdown(from: attributed)

        XCTAssertTrue(exported.contains("1. Parent 1"), exported)
        XCTAssertTrue(exported.contains("  - Child bullet"), exported)
        XCTAssertTrue(exported.contains("2. Parent 2"), exported)
        XCTAssertFalse(exported.contains("1. Parent 2"), exported)
    }

    func testListKindTransitionWithoutIdentityInsertsBlankLine() {
        var attributed = AttributedString("Bullet\nOrdered")
        let ranges = lineRanges(in: attributed)
        XCTAssertEqual(ranges.count, 2)

        attributed[ranges[0]].blockKind = .bulletList
        attributed[ranges[0]].listDepth = 1
        attributed[ranges[1]].blockKind = .orderedList
        attributed[ranges[1]].listDepth = 1

        let exported = MarkdownExporter().markdown(from: attributed)

        XCTAssertEqual(exported, "- Bullet\n\n1. Ordered", exported)
    }

    func testUnorderedListTransitionsWithoutIdentityStayContiguous() {
        var attributed = AttributedString("Bullet\nOpen\nDone")
        let ranges = lineRanges(in: attributed)
        XCTAssertEqual(ranges.count, 3)

        attributed[ranges[0]].blockKind = .bulletList
        attributed[ranges[0]].listDepth = 1
        attributed[ranges[1]].blockKind = .taskUnchecked
        attributed[ranges[1]].listDepth = 1
        attributed[ranges[2]].blockKind = .taskChecked
        attributed[ranges[2]].listDepth = 1

        let exported = MarkdownExporter().markdown(from: attributed)

        XCTAssertEqual(exported, "- Bullet\n- [ ] Open\n- [x] Done", exported)
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

    func testConstrainedDocumentPreservesBlockquoteListSemantics() {
        let markdown = """
        > - Item 1
        > - Item 2
        """
        let importer = MarkdownImporter()
        let exporter = MarkdownExporter()

        let imported = importer.attributedString(from: markdown).attributedString
        let constrained = MarkdownFormattingDefinition().constrainedDocument(imported)
        let exported = exporter.markdown(from: constrained)

        XCTAssertTrue(exported.contains("> - Item 1"), exported)
        XCTAssertTrue(exported.contains("> - Item 2"), exported)
        XCTAssertFalse(exported.contains("- Item 1\n- Item 2"), exported)
    }

    func testCodeBlockToHorizontalRuleUsesSingleBlankLineSeparator() {
        let markdown = """
        ```
        print("hello")
        ```

        ---
        """
        let importer = MarkdownImporter()
        let exporter = MarkdownExporter()

        let imported = importer.attributedString(from: markdown).attributedString
        let exported = exporter.markdown(from: imported)
        let expected = """
        ```
        print("hello")
        ```

        ---
        """

        XCTAssertEqual(exported, expected)
    }

    func testFixtureRoundTripStabilizesCanonicalMarkdown() throws {
        let markdown = try loadFixture(named: "TestNoteForReading")
        let importer = MarkdownImporter()
        let exporter = MarkdownExporter()

        let firstAttributed = importer.attributedString(from: markdown).attributedString
        let canonical = exporter.markdown(from: firstAttributed)
        let secondAttributed = importer.attributedString(from: canonical).attributedString
        let canonicalAgain = exporter.markdown(from: secondAttributed)

        XCTAssertEqual(canonicalAgain, canonical)
    }

    func testGoldenFixturesExportCanonicalMarkdown() throws {
        let fixtures = try loadGoldenFixtures()
        XCTAssertFalse(fixtures.isEmpty, "Expected at least one golden markdown fixture")

        let importer = MarkdownImporter()
        let exporter = MarkdownExporter()

        for fixture in fixtures {
            let input = try String(contentsOf: fixture.inputURL, encoding: .utf8)
            let expectedCanonical = try String(contentsOf: fixture.canonicalURL, encoding: .utf8)
            let imported = importer.attributedString(from: input)
            let actualCanonical = exporter.markdown(
                from: imported.attributedString,
                frontmatter: imported.frontmatter
            )

            XCTAssertEqual(
                normalizedFixtureText(actualCanonical),
                normalizedFixtureText(expectedCanonical),
                "Fixture canonical mismatch: \(fixture.name)"
            )
        }
    }

    func testGoldenFixtureCanonicalRoundTripIsStable() throws {
        let fixtures = try loadGoldenFixtures()
        XCTAssertFalse(fixtures.isEmpty, "Expected at least one golden markdown fixture")

        let importer = MarkdownImporter()
        let exporter = MarkdownExporter()

        for fixture in fixtures {
            let canonical = try String(contentsOf: fixture.canonicalURL, encoding: .utf8)
            let imported = importer.attributedString(from: canonical)
            let reExported = exporter.markdown(
                from: imported.attributedString,
                frontmatter: imported.frontmatter
            )

            XCTAssertEqual(
                normalizedFixtureText(reExported),
                normalizedFixtureText(canonical),
                "Fixture round-trip instability: \(fixture.name)"
            )
        }
    }

    private func loadFixture(named name: String) throws -> String {
        let fileURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Markdown/\(name).md")
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private struct GoldenFixture {
        let name: String
        let inputURL: URL
        let canonicalURL: URL
    }

    private func loadGoldenFixtures() throws -> [GoldenFixture] {
        let fixturesDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Markdown")
        let fileManager = FileManager.default
        let fixtureURLs = try fileManager.contentsOfDirectory(
            at: fixturesDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        var fixtures: [GoldenFixture] = []
        for canonicalURL in fixtureURLs
            .filter({ $0.lastPathComponent.hasSuffix(".canonical.md") })
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let canonicalName = canonicalURL.deletingPathExtension().deletingPathExtension().lastPathComponent
            let baseName = canonicalName.replacingOccurrences(of: ".canonical", with: "")
            let preferredInput = fixturesDirectory.appendingPathComponent("\(baseName).input.md")
            let fallbackInput = fixturesDirectory.appendingPathComponent("\(baseName).md")
            let inputURL = fileManager.fileExists(atPath: preferredInput.path) ? preferredInput : fallbackInput

            XCTAssertTrue(
                fileManager.fileExists(atPath: inputURL.path),
                "Missing input fixture for canonical fixture \(canonicalURL.lastPathComponent)"
            )

            guard fileManager.fileExists(atPath: inputURL.path) else {
                continue
            }

            fixtures.append(
                GoldenFixture(
                    name: baseName,
                    inputURL: inputURL,
                    canonicalURL: canonicalURL
                )
            )
        }

        return fixtures
    }

    private func normalizedFixtureText(_ text: String) -> String {
        var normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        while normalized.hasSuffix("\n") {
            normalized.removeLast()
        }
        return normalized
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
