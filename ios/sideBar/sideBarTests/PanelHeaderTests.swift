import SwiftUI
import XCTest
@testable import sideBar

@MainActor
final class PanelHeaderTests: XCTestCase {
    func testHeaderChromeSkipsContainerGlassOnIOSInLightMode() {
        let chrome = PanelHeader<EmptyView>.chrome(
            isMacOS: false,
            colorScheme: .light
        )

        XCTAssertNil(chrome)
    }

    func testHeaderChromeSkipsContainerGlassOnMacOSInDarkMode() {
        let chrome = PanelHeader<EmptyView>.chrome(
            isMacOS: true,
            colorScheme: .dark
        )

        XCTAssertNil(chrome)
    }

    func testSearchablePanelHeaderMinHeightKeepsSearchRowWhenInlineSearchIsVisible() {
        let minHeight = LayoutMetrics.searchablePanelHeaderMinHeight(
            showsInlineSearch: true
        )

        XCTAssertEqual(minHeight, LayoutMetrics.panelHeaderMinHeight)
    }

    func testSearchablePanelHeaderMinHeightCollapsesRemovedSearchRowSpace() {
        let minHeight = LayoutMetrics.searchablePanelHeaderMinHeight(
            showsInlineSearch: false
        )

        XCTAssertEqual(minHeight, LayoutMetrics.appHeaderMinHeight)
    }

    func testCompactPhonePanelSectionHeaderMinHeightUsesMediumSpacing() {
        XCTAssertEqual(
            LayoutMetrics.compactPhonePanelSectionHeaderMinHeight,
            DesignTokens.Spacing.md
        )
    }

    func testCompactPhonePanelTopContentPaddingUsesMediumSpacing() {
        XCTAssertEqual(
            LayoutMetrics.compactPhonePanelTopContentPadding,
            DesignTokens.Spacing.md
        )
    }

    func testCompactPhoneSectionedPanelTopPaddingAdjustmentPullsContentUpByMediumSpacing() {
        XCTAssertEqual(
            LayoutMetrics.compactPhoneSectionedPanelTopPaddingAdjustment,
            -DesignTokens.Spacing.md
        )
    }

    func testCompactPhoneTasksPanelTopPaddingUsesExtraSmallSpacing() {
        XCTAssertEqual(
            LayoutMetrics.compactPhoneTasksPanelTopPadding,
            DesignTokens.Spacing.xs
        )
    }

    func testSidebarPanelBackgroundTokenUsesSidebarOnIOS() {
        XCTAssertEqual(
            PlatformTokens.sidebarPanelBackgroundToken(isMacOS: false),
            .sidebar
        )
    }

    func testSidebarPanelBackgroundTokenUsesSidebarOnMacOS() {
        XCTAssertEqual(
            PlatformTokens.sidebarPanelBackgroundToken(isMacOS: true),
            .sidebar
        )
    }

    func testSidebarPanelHeaderDoesNotUseStandaloneBackgroundLayer() {
        XCTAssertFalse(sidebarPanelHeaderUsesStandaloneBackground())
    }

    func testSidebarPanelListDoesNotUseStandaloneBackgroundLayer() {
        XCTAssertFalse(sidebarPanelListUsesStandaloneBackground())
    }

    func testSidebarPanelHeaderInlineSearchShadowBleedUsesSearchFieldAllowance() {
        XCTAssertEqual(
            sidebarPanelHeaderInlineSearchShadowBleed(showsInlineSearch: true),
            LayoutMetrics.inlineSearchFieldBottomShadowBleed
        )
    }

    func testSidebarPanelHeaderSkipsInlineSearchShadowBleedWithoutSearchField() {
        XCTAssertEqual(
            sidebarPanelHeaderInlineSearchShadowBleed(showsInlineSearch: false),
            0
        )
    }

    func testInlineSearchFieldBottomShadowBleedUsesExtraSmallSpacing() {
        XCTAssertEqual(
            LayoutMetrics.inlineSearchFieldBottomShadowBleed,
            DesignTokens.Spacing.xs
        )
    }

    func testPanelHeaderTitleStackUsesSpacingToken() throws {
        let normalized = try panelHeaderSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("VStack(alignment:.leading,spacing:DesignTokens.Spacing.xxxs)"))
        XCTAssertFalse(normalized.contains("VStack(alignment:.leading,spacing:2)"))
    }
}

private func panelHeaderSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sideBarRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = sideBarRoot
        .appendingPathComponent("sideBar")
        .appendingPathComponent("Design")
        .appendingPathComponent("Components")
        .appendingPathComponent("PanelHeader.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read PanelHeader.swift: \(error)", file: file, line: line)
        throw error
    }
}
