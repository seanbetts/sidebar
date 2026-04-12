import XCTest
@testable import sideBar

final class SiteHeaderBarTests: XCTestCase {
    func testDesktopTrailingActionChromeUsesSharedHeaderActionButtonStyle() {
        XCTAssertEqual(SiteHeaderBar.desktopTrailingActionChromeStyle, .glass)
    }

    func testDesktopTrailingActionChromeUsesSharedActionButtonGlass() {
        XCTAssertEqual(SiteHeaderBar.desktopTrailingActionChrome, .actionButton)
    }

    func testDesktopTrailingControlsSkipGroupedGlass() {
        XCTAssertFalse(SiteHeaderBar.usesGroupedGlass(forCompact: false))
    }

    func testCompactTrailingControlsSkipGroupedGlass() {
        XCTAssertFalse(SiteHeaderBar.usesGroupedGlass(forCompact: true))
    }

    func testDesktopTrailingActionSourceUsesSharedHeaderActionButtons() throws {
        let normalized = try siteHeaderBarSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertEqual(
            normalized.components(
                separatedBy: "HeaderActionButton("
            ).count - 1,
            2
        )
        XCTAssertEqual(
            normalized.components(
                separatedBy: "chromeStyle:Self.desktopTrailingActionChromeStyle"
            ).count - 1,
            2
        )
    }

    func testCompactTrailingActionSourceUsesGlobalAvatarRegionWithoutOuterGlassWrapper() throws {
        let normalized = try siteHeaderBarSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("privatevarcompactTrailingActionControls:someView{GlobalAvatarRegionControls()}"))
        XCTAssertFalse(normalized.contains(".glassChrome(Self.compactTrailingActionChrome)"))
    }

    func testDesktopScratchpadPopoverUsesSharedScratchpadSurface() throws {
        let normalized = try siteHeaderBarSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("ScratchpadPopoverSurface("))
        XCTAssertFalse(normalized.contains("MacPopoverShell(type:scratchpadPopoverPanelType())"))
    }

    func testSiteHeaderBarHandlesScratchpadShortcutWithoutIOSGuard() throws {
        let normalized = try siteHeaderBarSource()
            .normalizedForSourceAssertions()
        let scratchpadShortcutHandler =
            ".onReceive(environment.navigation.$shortcutActionEvent){eventin"
            + "guardletevent,event.action==.openScratchpad,"
            + "scratchpadPresentationStyle==.anchoredPopoverelse{return}"
            + "isScratchpadPresented=true}"

        XCTAssertTrue(
            normalized.contains(scratchpadShortcutHandler)
        )
        XCTAssertFalse(normalized.contains("#ifos(iOS).onReceive(environment.navigation.$shortcutActionEvent)"))
    }

    func testSiteHeaderBarSourceUsesSharedHeaderStatusControllerAndPopover() throws {
        let normalized = try siteHeaderBarSource().normalizedForSourceAssertions()

        XCTAssertTrue(normalized.contains("@StateObjectprivatevarheaderStatusController=HeaderStatusController()"))
        XCTAssertTrue(normalized.contains("privatevarheaderStatusCluster:someView"))
        XCTAssertTrue(normalized.contains("HeaderStatusPillButton("))
        XCTAssertFalse(normalized.contains("privatevarsyncStatusPill"))
        XCTAssertFalse(normalized.contains("privatevarsyncStatusText"))
        XCTAssertFalse(normalized.contains("privatevaringestionStatusText"))
        XCTAssertFalse(normalized.contains("environment.writeQueue.pendingCount>0||environment.writeQueue.failedCount>0"))
        XCTAssertFalse(normalized.contains("IngestionCenterView(viewModel:environment.ingestionViewModel)"))
    }
}

private extension String {
    func normalizedForSourceAssertions() -> String {
        replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }
}

private func siteHeaderBarSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sourceURL = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("sideBar")
        .appendingPathComponent("Views")
        .appendingPathComponent("Websites")
        .appendingPathComponent("SiteHeaderBar.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read SiteHeaderBar.swift: \(error)", file: file, line: line)
        throw error
    }
}
