import XCTest

final class GlobalAvatarRegionControlsSourceTests: XCTestCase {
    func testGlobalAvatarRegionUsesSharedSymbolScaleForProfileAndScratchpad() throws {
        let normalized = try profileAvatarSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("enumGlobalAvatarRegionMetrics{"))
        XCTAssertTrue(normalized.contains("staticletsymbolScaleFactor:CGFloat=0.7"))
        XCTAssertTrue(
            normalized.contains(
                "Image(systemName:\"person.crop.circle\")"
                    + ".appScaledFont("
                    + "size:size*GlobalAvatarRegionMetrics.symbolScaleFactor,"
                    + "weight:.regular)"
            )
        )
        XCTAssertTrue(
            normalized.contains(
                "Image(systemName:\"square.and.pencil\")"
                    + ".appScaledFont("
                    + "size:avatarSize*GlobalAvatarRegionMetrics.symbolScaleFactor,"
                    + "weight:.regular)"
            )
        )
        XCTAssertFalse(
            normalized.contains(
                "Image(systemName:\"square.and.pencil\").appFont(.labelMd)"
            )
        )
    }

    func testGlobalAvatarRegionUsesPlainScratchpadControlAndSharedScratchpadSurface() throws {
        let normalized = try profileAvatarSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertFalse(normalized.contains("HeaderActionButton(systemName:\"square.and.pencil\""))
        XCTAssertTrue(normalized.contains("ScratchpadPopoverSurface("))
    }

    func testGlobalAvatarRegionButtonsUseSharedHoverModifier() throws {
        let normalized = try profileAvatarSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("SettingsAvatarButton"))
        XCTAssertEqual(normalized.components(separatedBy: ".sidebarHover(").count - 1, 2)
        XCTAssertTrue(normalized.contains("DesignTokens.Colors.sidebarHoverBackground"))
    }

    private func profileAvatarSource(file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let sideBarRoot = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sideBarRoot
            .appendingPathComponent("sideBar")
            .appendingPathComponent("Views")
            .appendingPathComponent("Common")
            .appendingPathComponent("ProfileAvatarView.swift")

        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            XCTFail("Failed to read ProfileAvatarView.swift: \(error)", file: file, line: line)
            throw error
        }
    }
}
