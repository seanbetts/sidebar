import XCTest

final class HeaderSidebarIconSourceTests: XCTestCase {
    func testHeaderActionComponentsDoNotExposeStringIconCompatibilityApis() throws {
        let normalized = try source(at: ["sideBar", "Design", "Components", "HeaderActionIcon.swift"])
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("structHeaderActionIcon:View{leticon:AppIcon"))
        XCTAssertTrue(normalized.contains("structHeaderActionButton:View{leticon:AppIcon"))
        XCTAssertTrue(normalized.contains("structHeaderActionMenuControl<MenuContent:View>:View{leticon:AppIcon"))
        XCTAssertTrue(normalized.contains("structHeaderActionMenuButton:View{leticon:AppIcon"))
        XCTAssertTrue(normalized.contains("HeaderActionIcon(icon:icon)"))
        XCTAssertTrue(normalized.contains("Image(appIcon:icon)"))
        XCTAssertFalse(normalized.contains("init(systemName:String"))
        XCTAssertFalse(normalized.contains("init(systemImage:String"))
        XCTAssertFalse(normalized.contains("varsystemImage:String"))
        XCTAssertFalse(normalized.contains("AppIcon(rawValue:systemName)"))
        XCTAssertFalse(normalized.contains("AppIcon(rawValue:systemImage)"))
    }

    func testSidebarMenuItemsDoNotExposeStringIconCompatibilityApis() throws {
        let normalized = try source(at: ["sideBar", "Design", "Components", "SidebarMenuItem.swift"])
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("leticon:AppIcon?"))
        XCTAssertTrue(normalized.contains("Label(item.title,systemImage:icon.rawValue)"))
        XCTAssertFalse(normalized.contains("varsystemImage:String?"))
        XCTAssertFalse(normalized.contains("init(title:String,systemImage:String?"))
        XCTAssertFalse(normalized.contains("systemImage.map(AppIcon.init(rawValue:))"))
        XCTAssertFalse(normalized.contains("item.systemImage"))
    }

    func testHeaderExpandButtonsUseAppIconNavigationValues() throws {
        let chatHeader = try source(at: ["sideBar", "Views", "Chat", "ChatHeaderView.swift"])
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let notesDetail = try source(at: ["sideBar", "Views", "Notes", "NotesDetailView.swift"])
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        for source in [chatHeader, notesDetail] {
            XCTAssertTrue(source.contains("icon:expandButtonIcon"))
            XCTAssertTrue(source.contains("AppIcon.Navigation.expandWorkspace"))
            XCTAssertTrue(source.contains("AppIcon.Navigation.collapseWorkspace"))
            XCTAssertFalse(source.contains("systemName:expandButtonIconName"))
            XCTAssertFalse(source.contains("\"arrow.up.right.and.arrow.down.left\""))
            XCTAssertFalse(source.contains("\"arrow.down.left.and.arrow.up.right\""))
        }
    }
}

private func source(
    at pathComponents: [String],
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sideBarRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = pathComponents.reduce(sideBarRoot) { url, component in
        url.appendingPathComponent(component)
    }

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read \(pathComponents.joined(separator: "/")): \(error)", file: file, line: line)
        throw error
    }
}
