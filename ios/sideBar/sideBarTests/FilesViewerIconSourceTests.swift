import XCTest

final class FilesViewerIconSourceTests: XCTestCase {
    func testFilesViewerControlsRouteIconsThroughAppIcon() throws {
        let appIcon = try normalizedSource(at: ["sideBarShared", "Utilities", "AppIcon.swift"])
        let fileViewer = try normalizedSource(at: ["sideBar", "Views", "Files", "FileViewerView.swift"])
        let fileViewerComponents = try normalizedSource(
            at: ["sideBar", "Views", "Files", "FileViewerComponents.swift"]
        )
        let spreadsheetViewer = try normalizedSource(at: ["sideBar", "Views", "Files", "SpreadsheetViewer.swift"])

        XCTAssertTrue(appIcon.contains("publicstaticletopenExternal=AppIcon(rawValue:\"arrow.up.right.square\")"))
        XCTAssertTrue(appIcon.contains("publicstaticletplayFilled=AppIcon(rawValue:\"play.circle.fill\")"))
        XCTAssertTrue(appIcon.contains("enumSpreadsheet{"))
        XCTAssertTrue(
            appIcon.contains("publicstaticletfilterRows=AppIcon(rawValue:\"line.3.horizontal.decrease.circle\")")
        )
        XCTAssertTrue(appIcon.contains("publicstaticletsortAscending=AppIcon(rawValue:\"arrowtriangle.up.fill\")"))
        XCTAssertTrue(appIcon.contains("publicstaticletsortDescending=AppIcon(rawValue:\"arrowtriangle.down.fill\")"))

        XCTAssertTrue(fileViewer.contains("importsideBarShared"))
        XCTAssertTrue(fileViewer.contains("Label(\"OpeninYouTube\",systemImage:AppIcon.Action.openExternal.rawValue)"))
        XCTAssertFalse(fileViewer.contains("systemImage:\"arrow.up.right.square\""))

        XCTAssertTrue(fileViewerComponents.contains("importsideBarShared"))
        XCTAssertTrue(fileViewerComponents.contains("Image(appIcon:AppIcon.Media.playFilled)"))
        XCTAssertFalse(fileViewerComponents.contains("Image(systemName:\"play.circle.fill\")"))

        XCTAssertTrue(spreadsheetViewer.contains("Image(appIcon:AppIcon.Spreadsheet.filterRows)"))
        XCTAssertTrue(
            spreadsheetViewer.contains(
                "Image(appIcon:sortDirection==.ascending?AppIcon.Spreadsheet.sortAscending"
                    + ":AppIcon.Spreadsheet.sortDescending)"
            )
        )
        XCTAssertFalse(spreadsheetViewer.contains("Image(systemName:\"line.3.horizontal.decrease.circle\")"))
        XCTAssertFalse(spreadsheetViewer.contains("\"arrowtriangle.up.fill\""))
        XCTAssertFalse(spreadsheetViewer.contains("\"arrowtriangle.down.fill\""))
    }

    func testSpreadsheetFilterFieldUsesBodyTypography() throws {
        let spreadsheetViewer = try normalizedSource(at: ["sideBar", "Views", "Files", "SpreadsheetViewer.swift"])

        XCTAssertTrue(
            spreadsheetViewer.contains("TextField(\"Filterrows\",text:$filterText).textFieldStyle(.plain).appFont(.body)")
        )
        XCTAssertFalse(spreadsheetViewer.contains(".appFont(.subheading).padding(.horizontal,DesignTokens.Spacing.sm)"))
    }

    private func normalizedSource(
        at pathComponents: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let source = try source(at: pathComponents, file: file, line: line)
        return source.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }

    private func source(
        at pathComponents: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let sideBarRoot = fileURL.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = pathComponents.reduce(sideBarRoot) { url, component in
            url.appendingPathComponent(component)
        }

        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            XCTFail("Failed to read \(sourceURL.path): \(error)", file: file, line: line)
            throw error
        }
    }
}
