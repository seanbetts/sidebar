import XCTest

final class WidgetSignedOutViewTests: XCTestCase {
    func testHomeWidgetSignedOutViewUsesContrastAwareIconColor() throws {
        let normalized = try widgetListLayoutSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let expectedIconStyle =
            "Image(appIcon:AppIcon.Settings.profileWarning)"
            + ".font(.system(size:32))"
            + ".foregroundStyle(colorScheme==.dark?.white:.black)"

        XCTAssertTrue(normalized.contains("@Environment(\\.colorScheme)privatevarcolorScheme"))
        XCTAssertTrue(normalized.contains(expectedIconStyle))
        XCTAssertFalse(normalized.contains("Image(systemName:\"person.crop.circle.badge.exclamationmark\")"))
    }
}

private func widgetListLayoutSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sideBarRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = sideBarRoot
        .appendingPathComponent("sideBarWidgets")
        .appendingPathComponent("Widgets")
        .appendingPathComponent("WidgetListLayout.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read WidgetListLayout.swift: \(error)", file: file, line: line)
        throw error
    }
}
