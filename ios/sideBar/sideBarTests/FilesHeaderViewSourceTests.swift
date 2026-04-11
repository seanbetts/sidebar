import XCTest

final class FilesHeaderViewSourceTests: XCTestCase {
    func testFilesHeaderUsesFixedHeightWhenPdfControlsAreNotEmbedded() throws {
        let normalized = try filesHeaderViewSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(
            normalized.contains(
                ".frame(height:LayoutMetrics.contentHeaderMinHeight)"
            )
        )
        XCTAssertFalse(
            normalized.contains(
                ".frame(minHeight:LayoutMetrics.contentHeaderMinHeight,alignment:.leading)"
            )
        )
    }

    func testFilesHeaderDoesNotEmbedPdfControls() throws {
        let normalized = try filesHeaderViewSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(
            normalized.contains(
                "ContentHeaderRow("
            )
        )
        XCTAssertFalse(
            normalized.contains(
                "PdfViewerFloatingControls(controller:pdfController"
            )
        )
    }

    private func filesHeaderViewSource(file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let sideBarRoot = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sideBarRoot
            .appendingPathComponent("sideBar")
            .appendingPathComponent("Views")
            .appendingPathComponent("Files")
            .appendingPathComponent("FilesHeaderComponents.swift")

        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            XCTFail("Failed to read files header view source: \(error)", file: file, line: line)
            throw error
        }
    }
}
