import XCTest

final class NavigationIconSourceTests: XCTestCase {
    func testSidebarRailRoutesSectionIconsThroughAppIcon() throws {
        let source = try normalizedSource(at: ["sideBar", "Views", "SidebarRail.swift"])

        XCTAssertTrue(source.contains("Image(appIcon:section.appIcon)"))
        XCTAssertFalse(source.contains("Image(systemName:iconName(for:section))"))
        XCTAssertFalse(source.contains("privatefunciconName(forsection:AppSection)->String"))
        XCTAssertFalse(source.contains("section.iconName"))
    }

    func testCompactPhoneTabsRouteSectionIconsThroughAppIcon() throws {
        let layout = try normalizedSource(at: ["sideBar", "Views", "ContentView+Layout.swift"])
        let tabs = try normalizedSource(at: ["sideBar", "Views", "ContentView+CompactPhoneTabs.swift"])
        let phone = try normalizedSource(at: ["sideBar", "Views", "ContentView+Phone.swift"])

        XCTAssertTrue(layout.contains("Image(appIcon:compactPhoneTabAppIcon(for:tab))"))
        XCTAssertTrue(layout.contains("Image(appIcon:section.appIcon)"))
        XCTAssertFalse(layout.contains("Image(systemName:compactPhoneTabIconName(for:tab))"))
        XCTAssertFalse(layout.contains("Image(systemName:phoneIconName(for:section))"))

        XCTAssertTrue(tabs.contains("funccompactPhoneTabAppIcon(fortab:CompactPhoneTab)->AppIcon"))
        XCTAssertTrue(tabs.contains("staticfunccompactPhoneTabAppIcon("))
        XCTAssertTrue(tabs.contains("returnAppIcon.Action.more"))
        XCTAssertFalse(tabs.contains("funccompactPhoneTabIconName"))
        XCTAssertFalse(tabs.contains("return\"ellipsis\""))

        XCTAssertTrue(phone.contains("Image(appIcon:section.appIcon)"))
        XCTAssertFalse(phone.contains("iconName:phoneIconName(for:)"))
        XCTAssertFalse(phone.contains("funcphoneIconName(forsection:AppSection)->String"))
        XCTAssertFalse(phone.contains("Label(section.title,systemImage:iconName(section))"))
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
