import XCTest

final class FileViewerViewSourceTests: XCTestCase {
    func testPdfViewerUsesFloatingTopTrailingControlsOverlay() throws {
        let normalized = try fileViewerViewSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(
            normalized.contains(
                "PDFViewerContainer(url:url,controller:pdfController)"
                    + ".overlay(alignment:.topTrailing)"
                    + "{PdfViewerFloatingControls(controller:pdfController)"
                    + ".padding(.top,DesignTokens.Spacing.sm)"
                    + ".padding(.trailing,DesignTokens.Spacing.md)}"
            )
        )
    }

    func testIngestionDetailViewKeysMountedViewerBySelectionScopedIdentity() throws {
        let normalized = try ingestionDetailViewSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(
            normalized.contains(
                "FileViewerView(state:state,pdfController:pdfController)"
                    + ".id(Self.viewerResetIdentity("
            )
        )
    }

    private func fileViewerViewSource(file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let sideBarRoot = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sideBarRoot
            .appendingPathComponent("sideBar")
            .appendingPathComponent("Views")
            .appendingPathComponent("Files")
            .appendingPathComponent("FileViewerView.swift")

        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            XCTFail("Failed to read file viewer view source: \(error)", file: file, line: line)
            throw error
        }
    }

    private func ingestionDetailViewSource(file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let sideBarRoot = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sideBarRoot
            .appendingPathComponent("sideBar")
            .appendingPathComponent("Views")
            .appendingPathComponent("Files")
            .appendingPathComponent("IngestionDetailView.swift")

        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            XCTFail("Failed to read ingestion detail view source: \(error)", file: file, line: line)
            throw error
        }
    }
}
