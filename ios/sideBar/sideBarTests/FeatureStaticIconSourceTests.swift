import XCTest

final class FeatureStaticIconSourceTests: XCTestCase {
    func testSkillsStoreStaticChromeRoutesThroughAppIcon() throws {
        let appIcon = try normalizedSource(at: ["sideBarShared", "Utilities", "AppIcon.swift"])
        let cardComponents = try normalizedSource(
            at: ["sideBar", "Views", "SkillsStore", "SkillsStoreCardComponents.swift"]
        )
        let skillsStoreDetail = try normalizedSource(
            at: ["sideBar", "Views", "SkillsStore", "SkillsStoreDetailView.swift"]
        )

        XCTAssertTrue(appIcon.contains("publicstaticletcategoryAll=AppIcon(rawValue:\"square.grid.2x2\")"))
        XCTAssertTrue(cardComponents.contains("staticfuncappIcon(forraw:String)->AppIcon"))
        XCTAssertTrue(cardComponents.contains("returnAppIcon.Skills.categoryAll"))
        XCTAssertTrue(cardComponents.contains("leticon:AppIcon"))
        XCTAssertTrue(cardComponents.contains("Image(appIcon:icon)"))
        XCTAssertTrue(cardComponents.contains("SkillsStoreInstallPill(icon:AppIcon.State.successFilled"))
        XCTAssertTrue(cardComponents.contains("SkillsStoreInstallPill(icon:AppIcon.Action.addCircleFilled"))
        XCTAssertFalse(cardComponents.contains("Image(systemName:iconName)"))
        XCTAssertFalse(cardComponents.contains("Image(systemName:systemName)"))
        XCTAssertFalse(skillsStoreDetail.contains("iconName:SkillsStoreCategoryIcon.iconName"))
    }

    func testNotesSaveStatusRoutesThroughAppIcon() throws {
        let appIcon = try normalizedSource(at: ["sideBarShared", "Utilities", "AppIcon.swift"])
        let notesDetail = try normalizedSource(at: ["sideBar", "Views", "Notes", "NotesDetailView.swift"])

        XCTAssertTrue(appIcon.contains("publicstaticletqueuedForSync=AppIcon(rawValue:\"icloud.and.arrow.up\")"))
        XCTAssertTrue(appIcon.contains("publicstaticletunsavedChanges=AppIcon(rawValue:\"pencil.circle.fill\")"))
        XCTAssertTrue(notesDetail.contains("leticon:AppIcon"))
        XCTAssertTrue(notesDetail.contains("Image(appIcon:status.icon)"))
        XCTAssertTrue(notesDetail.contains("HeaderActionIcon(icon:status.icon)"))
        XCTAssertTrue(notesDetail.contains("icon:AppIcon.State.syncing"))
        XCTAssertTrue(notesDetail.contains("icon:AppIcon.State.queuedForSync"))
        XCTAssertTrue(notesDetail.contains("icon:AppIcon.State.warningFilled"))
        XCTAssertTrue(notesDetail.contains("icon:AppIcon.Notes.unsavedChanges"))
        XCTAssertTrue(notesDetail.contains("icon:AppIcon.State.successFilled"))
        XCTAssertFalse(notesDetail.contains("leticonName:String"))
        XCTAssertFalse(notesDetail.contains("iconName:\"arrow.triangle.2.circlepath\""))
        XCTAssertFalse(notesDetail.contains("iconName:\"icloud.and.arrow.up\""))
        XCTAssertFalse(notesDetail.contains("iconName:\"exclamationmark.triangle.fill\""))
        XCTAssertFalse(notesDetail.contains("iconName:\"pencil.circle.fill\""))
        XCTAssertFalse(notesDetail.contains("iconName:\"checkmark.circle.fill\""))
        XCTAssertFalse(notesDetail.contains("Image(systemName:status.iconName)"))
        XCTAssertFalse(notesDetail.contains("HeaderActionIcon(systemName:status.iconName)"))
    }

    private func normalizedSource(
        at pathComponents: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let source = try source(at: pathComponents, file: file, line: line)
        return source.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }

    private func source(
        at pathComponents: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let sideBarRoot = fileURL.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = pathComponents.reduce(sideBarRoot) { url, component in
            url.appendingPathComponent(component)
        }

        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            XCTFail("Failed to read \(sourceURL.path): \(error)", file: file, line: line)
            throw error
        }
    }
}
