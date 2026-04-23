import XCTest
@testable import sideBar

@MainActor
final class WebsiteReadingInsetsTests: XCTestCase {
    func testWebsiteDetailViewUsesSharedBottomReadingInsetMetric() {
        XCTAssertEqual(
            WebsitesDetailView.websiteContentBottomInset,
            DesignTokens.Spacing.xxl
        )
    }

    func testWebsiteDetailViewPassesBottomInsetToMarkdownContainer() throws {
        let normalized = try websiteDetailSource().normalizedForSourceAssertions()

        XCTAssertTrue(normalized.contains("additionalContentInsets:EdgeInsets("))
        XCTAssertTrue(normalized.contains("bottom:Self.websiteContentBottomInset"))
    }

    func testSideBarMarkdownContainerDefaultsAdditionalInsetsToZeroAndAppliesThemAfterBasePadding() throws {
        let normalized = try sideBarMarkdownSource().normalizedForSourceAssertions()

        XCTAssertTrue(normalized.contains("letadditionalContentInsets:EdgeInsets"))
        XCTAssertTrue(normalized.contains("additionalContentInsets:EdgeInsets=.init()"))
        XCTAssertTrue(normalized.contains("self.additionalContentInsets=additionalContentInsets"))
        XCTAssertTrue(normalized.contains(".padding(.vertical,SideBarMarkdownLayout.verticalPadding).padding(additionalContentInsets)"))
    }
}

private extension String {
    func normalizedForSourceAssertions() -> String {
        replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }
}

private func websiteDetailSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    try sourceFile(
        pathComponents: ["Views", "Websites", "WebsitesDetailView.swift"],
        file: file,
        line: line
    )
}

private func sideBarMarkdownSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    try sourceFile(
        pathComponents: ["Views", "Common", "SideBarMarkdown.swift"],
        file: file,
        line: line
    )
}

private func sourceFile(
    pathComponents: [String],
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    var sourceURL = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("sideBar")

    for component in pathComponents {
        sourceURL.appendPathComponent(component)
    }

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read \(pathComponents.joined(separator: "/")): \(error)", file: file, line: line)
        throw error
    }
}
