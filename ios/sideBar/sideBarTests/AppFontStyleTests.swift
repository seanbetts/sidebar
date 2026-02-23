import XCTest
@testable import sideBar

final class AppFontStyleTests: XCTestCase {
    func testFixedStyleUsesSelectedOptionMultiplier() {
        XCTAssertEqual(
            AppFontStyle.labelMd.pointSize(for: .system),
            14.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            AppFontStyle.labelMd.pointSize(for: .small),
            12.6,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            AppFontStyle.labelMd.pointSize(for: .medium),
            14.7,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            AppFontStyle.labelMd.pointSize(for: .large),
            16.8,
            accuracy: 0.0001
        )
    }

    func testPreferredStyleScalesRelativeToSystemSize() {
        let systemSize = AppFontStyle.subheadline.pointSize(for: .system)
        XCTAssertEqual(
            AppFontStyle.subheadline.pointSize(for: .small),
            systemSize * AppTextSizeOption.small.scaleMultiplier,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            AppFontStyle.subheadline.pointSize(for: .medium),
            systemSize * AppTextSizeOption.medium.scaleMultiplier,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            AppFontStyle.subheadline.pointSize(for: .large),
            systemSize * AppTextSizeOption.large.scaleMultiplier,
            accuracy: 0.0001
        )
    }

    func testPointSizeUsesPassedOptionInsteadOfStoredDefault() {
        let key = AppStorageKeys.appTextSize
        let defaults = UserDefaults.standard
        let original = defaults.string(forKey: key)
        defaults.set(AppTextSizeOption.large.rawValue, forKey: key)
        defer {
            if let original {
                defaults.set(original, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        XCTAssertEqual(
            AppFontStyle.labelMd.pointSize(for: .small),
            12.6,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            AppFontStyle.labelMd.pointSize(for: .large),
            16.8,
            accuracy: 0.0001
        )
    }
}
