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

    func testSidebarRailUsesPrimaryNavigationIconTokenForSectionIcons() throws {
        let normalized = try sidebarRailSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains(".appFont(.titleSm)"))
        XCTAssertTrue(normalized.contains(".frame(width:DesignTokens.Icon.xl,height:DesignTokens.Icon.xl)"))
        XCTAssertFalse(normalized.contains(".appFont(.label)"))
        XCTAssertFalse(normalized.contains(".font(.system(size:18,weight:.semibold))"))
    }

    func testSidebarRailUsesTokensForButtonFramesAndNamedLogoException() throws {
        let normalized = try sidebarRailSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("staticletlogoSize:CGFloat=26"))
        XCTAssertTrue(normalized.contains(".frame(width:Self.logoSize,height:Self.logoSize)"))
        XCTAssertTrue(normalized.contains(".frame(width:DesignTokens.Icon.xl,height:DesignTokens.Icon.xl)"))
        XCTAssertTrue(normalized.contains("ProfileAvatarView(size:DesignTokens.Icon.xl)"))
        XCTAssertFalse(normalized.contains(".frame(width:26,height:26)"))
        XCTAssertFalse(normalized.contains(".frame(width:32,height:32)"))
        XCTAssertFalse(normalized.contains("ProfileAvatarView(size:32)"))
    }

    func testSidebarRailStackSpacingUsesTokens() throws {
        let normalized = try sidebarRailSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("VStack(spacing:DesignTokens.Spacing.md)"))
        XCTAssertTrue(normalized.contains("VStack(spacing:DesignTokens.Spacing.sm)"))
        XCTAssertFalse(normalized.contains("VStack(spacing:16)"))
        XCTAssertFalse(normalized.contains("VStack(spacing:12)"))
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
