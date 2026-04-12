import XCTest

final class PdfResizeDebugTraceSourceTests: XCTestCase {
    func testPdfResizeDebugTraceUtilityHasBeenRemoved() {
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: pdfResizeDebugTraceSourceURL.path),
            "Expected PDF resize debug trace utility to be removed"
        )
    }

    func testPdfViewerSourcesDoNotReferencePdfResizeDebugTrace() throws {
        for sourceURL in pdfViewerSourceURLs {
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            XCTAssertFalse(
                source.contains("PDFResizeDebugTrace"),
                "Expected \(sourceURL.lastPathComponent) to avoid PDF resize debug trace references"
            )
        }
    }

    private var sideBarRootURL: URL {
        let fileURL = URL(fileURLWithPath: #filePath)
        return fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var pdfResizeDebugTraceSourceURL: URL {
        sideBarRootURL
            .appendingPathComponent("sideBar")
            .appendingPathComponent("Utilities")
            .appendingPathComponent("PDFResizeDebugTrace.swift")
    }

    private var pdfViewerSourceURLs: [URL] {
        let filesRootURL = sideBarRootURL
            .appendingPathComponent("sideBar")
            .appendingPathComponent("Views")
            .appendingPathComponent("Files")

        return [
            filesRootURL.appendingPathComponent("FileViewerComponents.swift"),
            filesRootURL.appendingPathComponent("FileViewerPlatformComponents.swift"),
            filesRootURL.appendingPathComponent("FilesView.swift")
        ]
    }
}
