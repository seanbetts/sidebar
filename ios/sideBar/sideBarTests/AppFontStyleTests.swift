import XCTest
@testable import sideBar

final class AppFontStyleTests: XCTestCase {
    func testFixedStyleUsesSelectedOptionMultiplier() {
        XCTAssertEqual(
            AppFontStyle.label.pointSize(for: .system),
            14.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            AppFontStyle.label.pointSize(for: .small),
            11.2,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            AppFontStyle.label.pointSize(for: .medium),
            12.6,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            AppFontStyle.label.pointSize(for: .large),
            14.7,
            accuracy: 0.0001
        )
    }

    func testPreferredStyleScalesRelativeToSystemSize() {
        let systemSize = AppFontStyle.subheading.pointSize(for: .system)
        XCTAssertEqual(
            AppFontStyle.subheading.pointSize(for: .small),
            systemSize * AppTextSizeOption.small.scaleMultiplier,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            AppFontStyle.subheading.pointSize(for: .medium),
            systemSize * AppTextSizeOption.medium.scaleMultiplier,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            AppFontStyle.subheading.pointSize(for: .large),
            systemSize * AppTextSizeOption.large.scaleMultiplier,
            accuracy: 0.0001
        )
    }

    func testPointSizeUsesPassedOptionForEachCallWithoutSharedState() {
        XCTAssertEqual(
            AppFontStyle.label.pointSize(for: .small),
            11.2,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            AppFontStyle.label.pointSize(for: .large),
            14.7,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            AppFontStyle.label.pointSize(for: .small),
            11.2,
            accuracy: 0.0001
        )
    }

    func testAdditionalStylesScaleWithConfiguredOption() {
        XCTAssertEqual(
            AppFontStyle.badge.pointSize(for: .medium),
            9.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            AppFontStyle.titleSm.pointSize(for: .large),
            18.9,
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
            AppFontStyle.displayMd.pointSize(for: .system),
            24.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            AppFontStyle.displayLg.pointSize(for: .system),
            32.0,
            accuracy: 0.0001
        )

        let monoLabelSystem = AppFontStyle.monoLabel.pointSize(for: .system)
        XCTAssertEqual(
            AppFontStyle.monoLabel.pointSize(for: .small),
            monoLabelSystem * AppTextSizeOption.small.scaleMultiplier,
            accuracy: 0.0001
        )
    }

    func testRationalizedScaleRemovesDeprecatedStyleCasesAndSemiboldWeights() throws {
        let source = try appFontStyleSource()
        let deprecatedNames = [
            "title2Semibold",
            "title3Semibold",
            "size16Semibold",
            "labelMd",
            "bodySemibold",
            "headline",
            "subheadline",
            "subheadlineSemibold",
            "callout",
            "footnoteSemibold",
            "captionSemibold",
            "caption2",
            "caption2Semibold",
            "size10Bold",
            "size18Semibold",
            "size24Semibold",
            "size32Regular",
            "size32Semibold"
        ]

        for deprecatedName in deprecatedNames {
            XCTAssertFalse(source.contains(deprecatedName), "\(deprecatedName) should not remain in AppFontStyle")
        }
        XCTAssertFalse(source.contains(".semibold"), "AppFontStyle should use regular and bold weights only")
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

    private func appFontStyleSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root
            .appendingPathComponent("sideBar")
            .appendingPathComponent("Design")
            .appendingPathComponent("AppFontStyle.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }
}
