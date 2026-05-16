import SwiftUI
import XCTest
@testable import sideBar

@MainActor
final class SettingsMacStylesTests: XCTestCase {
    func testStatusBannerUsesSharedCardChrome() {
        XCTAssertEqual(SettingsMacStatusBanner.chromeKind, .card)
    }

    func testPanelCardUsesSharedCardChrome() {
        XCTAssertEqual(SettingsMacPanelCard<EmptyView>.chromeKind, .card)
    }

    func testSkillRowUsesSharedCardChrome() {
        XCTAssertEqual(SettingsMacSkillRow<EmptyView>.chromeKind, .card)
    }

    func testSettingsMacStylesRoutesPanelCardsStatusBannersAndSkillRowsThroughGlassChrome() throws {
        let normalized = try settingsMacStylesSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertEqual(
            normalized.components(separatedBy: ".glassChrome(Self.chromeKind)").count - 1,
            3
        )
    }
}

private func settingsMacStylesSource(
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
        .appendingPathComponent("Settings")
        .appendingPathComponent("SettingsMacStyles.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read SettingsMacStyles.swift: \(error)", file: file, line: line)
        throw error
    }
}
