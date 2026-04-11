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
            11.2,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            AppFontStyle.labelMd.pointSize(for: .medium),
            12.6,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            AppFontStyle.labelMd.pointSize(for: .large),
            14.7,
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

    func testPointSizeUsesPassedOptionForEachCallWithoutSharedState() {
        XCTAssertEqual(
            AppFontStyle.labelMd.pointSize(for: .small),
            11.2,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            AppFontStyle.labelMd.pointSize(for: .large),
            14.7,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            AppFontStyle.labelMd.pointSize(for: .small),
            11.2,
            accuracy: 0.0001
        )
    }

    func testAdditionalStylesScaleWithConfiguredOption() {
        XCTAssertEqual(
            AppFontStyle.size10Bold.pointSize(for: .medium),
            9.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            AppFontStyle.size16Semibold.pointSize(for: .large),
            16.8,
            accuracy: 0.0001
        )

        let monoBodySystem = AppFontStyle.monoBody.pointSize(for: .system)
        XCTAssertEqual(
            AppFontStyle.monoBody.pointSize(for: .small),
            monoBodySystem * AppTextSizeOption.small.scaleMultiplier,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            AppFontStyle.monoBody.pointSize(for: .large),
            monoBodySystem * AppTextSizeOption.large.scaleMultiplier,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            AppFontStyle.footnote.pointSize(for: .medium),
            AppFontStyle.footnoteSemibold.pointSize(for: .medium),
            accuracy: 0.0001
        )
        XCTAssertEqual(
            AppFontStyle.title2.pointSize(for: .large),
            AppFontStyle.title2Semibold.pointSize(for: .large),
            accuracy: 0.0001
        )

        let monoLabelSystem = AppFontStyle.monoLabel.pointSize(for: .system)
        XCTAssertEqual(
            AppFontStyle.monoLabel.pointSize(for: .small),
            monoLabelSystem * AppTextSizeOption.small.scaleMultiplier,
            accuracy: 0.0001
        )
    }

    func testScaledPointSizeHelperUsesOptionMultiplier() {
        XCTAssertEqual(
            AppFontStyle.scaledPointSize(14, for: .small),
            11.2,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            AppFontStyle.scaledPointSize(14, for: .medium),
            12.6,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            AppFontStyle.scaledPointSize(14, for: .large),
            14.7,
            accuracy: 0.0001
        )
    }

    func testScaledMetricHelperTracksBodyScaleAcrossOptions() {
        let systemMetric = AppFontStyle.scaledMetric(40, for: .system)
        let smallMetric = AppFontStyle.scaledMetric(40, for: .small)
        let largeMetric = AppFontStyle.scaledMetric(40, for: .large)

        XCTAssertLessThan(smallMetric, systemMetric)
        XCTAssertGreaterThan(largeMetric, systemMetric)
        XCTAssertEqual(
            largeMetric / smallMetric,
            AppFontStyle.body.pointSize(for: .large) / AppFontStyle.body.pointSize(for: .small),
            accuracy: 0.0001
        )
    }
}
