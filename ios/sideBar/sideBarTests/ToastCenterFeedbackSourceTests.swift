import XCTest

@testable import sideBar

final class ToastCenterFeedbackSourceTests: XCTestCase {
    func testToastCenterShowsMatchingHapticForToastStyle() throws {
        let normalized = try toastCenterSource()

        XCTAssertTrue(normalized.contains("Haptics.notification(style.hapticType)"))
    }

    func testToastStylesMapToMatchingNotificationHaptics() throws {
        let normalized = try toastCenterSource()

        XCTAssertTrue(normalized.contains("case.error:return.error"))
        XCTAssertTrue(normalized.contains("case.success:return.success"))
    }

    func testToastBannerUsesGlassChromeInsteadOfFlatSemanticFill() throws {
        let normalized = try toastCenterSource()

        XCTAssertTrue(normalized.contains("structToastBannerChromeModifier:ViewModifier{"))
        XCTAssertTrue(normalized.contains("content.glassEffect(.regular,in:Capsule())"))
        XCTAssertTrue(normalized.contains("content.background(.ultraThinMaterial,in:Capsule())"))
        XCTAssertFalse(normalized.contains(".background(toast.style.background)"))
    }

    func testToastBannerUsesCurrentSubheadingTypographyToken() throws {
        let normalized = try toastCenterSource()

        XCTAssertTrue(normalized.contains(".appFont(.subheading)"))
        XCTAssertFalse(normalized.contains(".appFont(.subheadlineSemibold)"))
    }

    private func toastCenterSource() throws -> String {
        try source(named: "ToastCenter.swift")
    }

    private func source(named filename: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let matches = try FileManager.default.subpathsOfDirectory(atPath: root.path)
            .filter { $0.hasSuffix(filename) }
        guard let relativePath = matches.first else {
            throw NSError(domain: "ToastCenterFeedbackSourceTests", code: 1)
        }
        let url = root.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }
}
