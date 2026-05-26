import XCTest

final class FilesViewerIconSourceTests: XCTestCase {
    func testFilesViewerControlsRouteIconsThroughAppIcon() throws {
        let appIcon = try StaticSourceGuard.normalizedSource(at: ["sideBarShared", "Utilities", "AppIcon.swift"])
        let fileViewer = try StaticSourceGuard.normalizedSource(
            at: ["sideBar", "Views", "Files", "FileViewerView.swift"]
        )
        let fileViewerComponents = try StaticSourceGuard.normalizedSource(
            at: ["sideBar", "Views", "Files", "FileViewerComponents.swift"]
        )
        let spreadsheetViewer = try StaticSourceGuard.normalizedSource(
            at: ["sideBar", "Views", "Files", "SpreadsheetViewer.swift"]
        )

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
        let spreadsheetViewer = try StaticSourceGuard.normalizedSource(
            at: ["sideBar", "Views", "Files", "SpreadsheetViewer.swift"]
        )

        XCTAssertTrue(
            spreadsheetViewer.contains("TextField(\"Filterrows\",text:$filterText).textFieldStyle(.plain).appFont(.body)")
        )
        XCTAssertFalse(spreadsheetViewer.contains(".appFont(.subheading).padding(.horizontal,DesignTokens.Spacing.sm)"))
    }

    func testSpreadsheetGridLayoutAvoidsPrecomputingEveryCellAttribute() throws {
        let spreadsheetGrid = try StaticSourceGuard.normalizedSource(
            at: ["sideBar", "Views", "Files", "SpreadsheetGridView.swift"]
        )

        XCTAssertFalse(spreadsheetGrid.contains("cachedAttributes"))
        XCTAssertFalse(spreadsheetGrid.contains("forrowin0..<rowCount{forcolumnin0..<columnCount"))
    }
}
