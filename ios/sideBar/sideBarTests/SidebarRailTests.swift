import XCTest
@testable import sideBar

final class SidebarRailTests: XCTestCase {
    func testSidebarRailUsesSharedActionButtonChromeForActiveSections() {
        let chrome = SidebarRail.buttonChrome(isActive: true, isHovered: false)

        XCTAssertEqual(chrome, .actionButton)
    }

    func testSidebarRailUsesSharedActionButtonChromeForHoveredSections() {
        let chrome = SidebarRail.buttonChrome(isActive: false, isHovered: true)

        XCTAssertEqual(chrome, .actionButton)
    }

    func testSidebarRailKeepsInactiveSectionsChromeFree() {
        let chrome = SidebarRail.buttonChrome(isActive: false, isHovered: false)

        XCTAssertNil(chrome)
    }

    func testSidebarRailSourceUsesSharedHoverModifierForSectionsAndAccessoryButtons() throws {
        let normalized = try sidebarRailSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains(".sidebarHover(Binding("))
        XCTAssertTrue(normalized.contains("hoveredSection==section"))
        XCTAssertTrue(normalized.contains("DesignTokens.Colors.sidebarHoverBackground"))
        XCTAssertFalse(normalized.contains(".onHover{"))
        XCTAssertFalse(normalized.contains("#ifos(macOS).onHover"))
    }

    func testSidebarRailUsesAppFontTokenForSectionIcons() throws {
        let normalized = try sidebarRailSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains(".appFont(.labelMd)"))
        XCTAssertFalse(normalized.contains(".font(.system(size:18,weight:.semibold))"))
    }
}

private func sidebarRailSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sideBarRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = sideBarRoot
        .appendingPathComponent("sideBar")
        .appendingPathComponent("Views")
        .appendingPathComponent("SidebarRail.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read SidebarRail.swift: \(error)", file: file, line: line)
        throw error
    }
}
