import XCTest

final class PdfViewerFloatingControlsSourceTests: XCTestCase {
    func testPdfViewerFloatingControlsUsesPlatformPopoverOverlays() throws {
        let normalized = try filesViewComponentsSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(
            normalized.contains("ZStack(alignment:.topTrailing){")
        )
        XCTAssertTrue(
            normalized.contains(
                "UIKitPDFControlBarRepresentable(configuration:configuration,showsVisibleChrome:false)"
            )
        )
        XCTAssertTrue(
            normalized.contains(
                "AppKitPDFControlOverlay(configuration:configuration,showsVisibleChrome:false)"
            )
        )
    }

    func testPdfControlPopoverActionsDoNotDismissOnInternalTap() throws {
        let normalized = try pdfControlBarSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertFalse(normalized.contains("action()onDismissRequested()"))
        XCTAssertFalse(normalized.contains("configuration.onSetFitMode(mode)onDismissRequested()"))
    }

    private func filesViewComponentsSource(file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let sideBarRoot = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sideBarRoot
            .appendingPathComponent("sideBar")
            .appendingPathComponent("Views")
            .appendingPathComponent("Files")
            .appendingPathComponent("FilesViewComponents.swift")

        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            XCTFail("Failed to read files view components source: \(error)", file: file, line: line)
            throw error
        }
    }

    private func pdfControlBarSource(file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let sideBarRoot = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sideBarRoot
            .appendingPathComponent("sideBar")
            .appendingPathComponent("Views")
            .appendingPathComponent("Files")
            .appendingPathComponent("PDFControlBar.swift")

        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            XCTFail("Failed to read PDF control bar source: \(error)", file: file, line: line)
            throw error
        }
    }
}
