import XCTest
@testable import sideBar

final class SidebarTypographyTests: XCTestCase {
    func testPrimaryMatchesBodyAcrossTextSizeOptions() {
        for option in AppTextSizeOption.allCases {
            XCTAssertEqual(
                SidebarTypography.primary.pointSize(for: option),
                AppFontStyle.body.pointSize(for: option),
                accuracy: 0.0001
            )
        }
    }

    func testSecondaryMatchesCaptionAcrossTextSizeOptions() {
        for option in AppTextSizeOption.allCases {
            XCTAssertEqual(
                SidebarTypography.secondary.pointSize(for: option),
                AppFontStyle.caption.pointSize(for: option),
                accuracy: 0.0001
            )
        }
    }

    func testTertiaryMatchesCaption2AcrossTextSizeOptions() {
        for option in AppTextSizeOption.allCases {
            XCTAssertEqual(
                SidebarTypography.tertiary.pointSize(for: option),
                AppFontStyle.caption2.pointSize(for: option),
                accuracy: 0.0001
            )
        }
    }
}
