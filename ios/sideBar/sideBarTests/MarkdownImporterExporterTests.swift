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
}
