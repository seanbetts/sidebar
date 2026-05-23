import XCTest

final class WebsiteHeaderIconSourceTests: XCTestCase {
    func testWebsiteHeaderIconVocabularyExists() throws {
        let appIcon = try normalizedSource(at: ["sideBarShared", "Utilities", "AppIcon.swift"])

        XCTAssertTrue(appIcon.contains("publicstaticletswapPanels=AppIcon(rawValue:\"arrow.left.arrow.right\")"))
        XCTAssertTrue(appIcon.contains("publicstaticletweather=AppIcon(rawValue:\"cloud.sun\")"))
    }

    func testWebsiteQuickActionsRouteIconsThroughAppIcon() throws {
        let source = try normalizedSource(
            at: ["sideBar", "Views", "Websites", "WebsitesDetailView+MenuActions.swift"]
        )

        XCTAssertTrue(source.contains("icon:isPinned?AppIcon.Action.unpin:AppIcon.Action.pin"))
        XCTAssertTrue(source.contains("icon:isArchived?AppIcon.Action.unarchive:AppIcon.Action.archive"))
        XCTAssertTrue(source.contains("icon:AppIcon.Action.delete"))
        XCTAssertTrue(source.contains("Image(appIcon:icon)"))
        XCTAssertFalse(source.contains("iconButton(systemName:"))
        XCTAssertFalse(source.contains("Image(systemName:systemName)"))
        XCTAssertFalse(source.contains("\"pin.slash\""))
        XCTAssertFalse(source.contains("\"archivebox.fill\""))
        XCTAssertFalse(source.contains("systemName:\"trash\""))
    }

    func testSiteHeaderBarRoutesHeaderControlsThroughAppIcon() throws {
        let source = try normalizedSource(at: ["sideBar", "Views", "Websites", "SiteHeaderBar.swift"])

        XCTAssertTrue(source.contains("HeaderInfoItem(icon:AppIcon.State.weather"))
        XCTAssertTrue(source.contains("HeaderActionButton(icon:AppIcon.Action.swapPanels"))
        XCTAssertTrue(source.contains("HeaderActionButton(icon:AppIcon.Content.scratchpad"))
        XCTAssertTrue(source.contains("leticon:AppIcon"))
        XCTAssertTrue(source.contains("Image(appIcon:icon)"))
        XCTAssertFalse(source.contains("HeaderInfoItem(icon:\"cloud.sun\""))
        XCTAssertFalse(source.contains("systemName:\"arrow.left.arrow.right\""))
        XCTAssertFalse(source.contains("systemName:\"square.and.pencil\""))
        XCTAssertFalse(source.contains("Image(systemName:icon)"))
    }

    func testHeaderStatusPopoverRoutesRowActionsThroughAppIcon() throws {
        let source = try normalizedSource(
            at: ["sideBar", "Views", "Websites", "HeaderStatus", "HeaderStatusPopover.swift"]
        )

        XCTAssertTrue(source.contains("Image(appIcon:actionAppIcon(action))"))
        XCTAssertTrue(source.contains("returnAppIcon.State.retry"))
        XCTAssertTrue(source.contains("returnAppIcon.Action.close"))
        XCTAssertFalse(source.contains("Image(systemName:actionSymbolName(action))"))
        XCTAssertFalse(source.contains("funcactionSymbolName"))
        XCTAssertFalse(source.contains("return\"arrow.clockwise\""))
        XCTAssertFalse(source.contains("return\"xmark\""))
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
