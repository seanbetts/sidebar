import SwiftUI
import XCTest
@testable import sideBar

final class PanelHeaderTests: XCTestCase {
    func testBackgroundStyleUsesSidebarOnIOSInLightMode() {
        let style = PanelHeader<EmptyView>.backgroundStyle(
            isMacOS: false,
            colorScheme: .light
        )

        XCTAssertEqual(style, .sidebar)
    }

    func testBackgroundStyleUsesSidebarOnIOSInDarkMode() {
        let style = PanelHeader<EmptyView>.backgroundStyle(
            isMacOS: false,
            colorScheme: .dark
        )

        XCTAssertEqual(style, .sidebar)
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
}
