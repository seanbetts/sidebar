import XCTest

final class Task15PDFIconSourceTests: XCTestCase {
    func testPdfControlBarRoutesControlIconsThroughAppIcon() throws {
        let normalized = try source(at: [
            "sideBar", "Views", "Files", "PDFControlBar.swift"
        ])
        .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("HeaderActionMenuControl(icon:AppIcon.PDF.fitPage"))
        XCTAssertTrue(normalized.contains("Label(\"Previouspage\",systemImage:AppIcon.Navigation.back.rawValue)"))
        XCTAssertTrue(normalized.contains("Label(\"Nextpage\",systemImage:AppIcon.Navigation.forward.rawValue)"))
        XCTAssertTrue(normalized.contains("Label(\"Zoomout\",systemImage:AppIcon.PDF.zoomOut.rawValue)"))
        XCTAssertTrue(normalized.contains("Label(\"Zoomin\",systemImage:AppIcon.PDF.zoomIn.rawValue)"))
        XCTAssertTrue(normalized.contains("fitModeButton(\"Fittoheight\",icon:AppIcon.PDF.fitHeight,mode:.height)"))
        XCTAssertTrue(normalized.contains("fitModeButton(\"Fittowidth\",icon:AppIcon.PDF.fitWidth,mode:.width)"))
        XCTAssertTrue(normalized.contains("Label(title,systemImage:AppIcon.State.success.rawValue)"))
        XCTAssertTrue(normalized.contains("Label(title,systemImage:icon.rawValue)"))
        XCTAssertTrue(normalized.contains("compactButton(icon:AppIcon.Navigation.back"))
        XCTAssertTrue(normalized.contains("compactButton(icon:AppIcon.Navigation.forward"))
        XCTAssertTrue(normalized.contains("compactButton(icon:AppIcon.PDF.zoomOut"))
        XCTAssertTrue(normalized.contains("compactButton(icon:AppIcon.PDF.zoomIn"))
        XCTAssertTrue(normalized.contains("fitIconButton(icon:AppIcon.PDF.fitWidth"))
        XCTAssertTrue(normalized.contains("fitIconButton(icon:AppIcon.PDF.fitHeight"))
        XCTAssertTrue(normalized.contains("Image(appIcon:icon)"))

        for rawSnippet in [
            "systemName:\"doc.viewfinder\"",
            "systemImage:\"chevron.left\"",
            "systemImage:\"chevron.right\"",
            "systemImage:\"minus.magnifyingglass\"",
            "systemImage:\"plus.magnifyingglass\"",
            "systemImage:\"distribute.vertical\"",
            "systemImage:\"distribute.horizontal\"",
            "systemImage:\"checkmark\"",
            "systemName:\"minus\"",
            "systemName:\"plus\""
        ] {
            XCTAssertFalse(normalized.contains(rawSnippet), "Found raw PDF control icon snippet: \(rawSnippet)")
        }
    }

    func testNativePdfControlBarsUseAppIconForEntrySymbol() throws {
        let uiKit = try source(at: [
            "sideBar", "Views", "Files", "UIKitPDFControlBar.swift"
        ])
        .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let appKit = try source(at: [
            "sideBar", "Views", "Files", "AppKitPDFControlBar.swift"
        ])
        .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(uiKit.contains("UIImage(systemName:AppIcon.PDF.fitPage.rawValue"))
        XCTAssertFalse(uiKit.contains("systemName:\"doc.viewfinder\""))
        XCTAssertTrue(appKit.contains("NSImage(systemSymbolName:AppIcon.PDF.fitPage.rawValue"))
        XCTAssertFalse(appKit.contains("systemSymbolName:\"doc.viewfinder\""))
    }

    private func source(
        at components: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let sideBarRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = components.reduce(sideBarRoot) { url, component in
            url.appendingPathComponent(component)
        }

        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            XCTFail("Failed to read source at \(sourceURL.path): \(error)", file: file, line: line)
            throw error
        }
    }
}
