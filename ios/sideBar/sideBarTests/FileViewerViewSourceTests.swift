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

    func testIngestionDetailViewDoesNotKeyMountedViewerIdentity() throws {
        let normalized = try ingestionDetailViewSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertFalse(
            normalized.contains("FileViewerView(state:state,pdfController:pdfController).id(")
        )
    }

    func testFileViewerKeysStatefulMediaSubviewsByURLIdentity() throws {
        let normalized = try fileViewerViewSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(
            normalized.contains("AudioPlayerView(url:url).id(url)")
        )
        XCTAssertTrue(
            normalized.contains("VideoPlayerContainer(url:url).id(url)")
        )
    }

    func testPdfFloatingControlsUseSingleNativeControlSurfaceOnModernOS() throws {
        let normalized = try filesViewComponentsSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertFalse(
            normalized.contains("ZStack(alignment:.topTrailing){PDFControlBar(configuration:configuration)")
        )
        let modernIOSControls =
            "if#available(iOS26.0,*){UIKitPDFControlBarRepresentable(configuration:configuration,showsVisibleChrome:true)"
        XCTAssertTrue(
            normalized.contains(modernIOSControls)
        )
        let modernMacControls =
            "if#available(macOS26.0,*){AppKitPDFControlOverlay(configuration:configuration,showsVisibleChrome:true)"
        XCTAssertTrue(
            normalized.contains(modernMacControls)
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
}
