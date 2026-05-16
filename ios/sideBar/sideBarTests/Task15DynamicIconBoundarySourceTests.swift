import XCTest

final class Task15DynamicIconBoundarySourceTests: XCTestCase {
    func testDynamicSwiftUIIconBoundariesRenderThroughAppIconAdapters() throws {
        let skillIconView = try normalizedSource(at: ["sideBar", "Views", "Common", "SkillIconView.swift"])
        let settingsMac = try normalizedSource(at: ["sideBar", "Views", "Settings", "SettingsMacStyles.swift"])
        let agentWorkspace = try normalizedSource(
            at: ["sideBar", "Views", "AgentWorkspace", "AgentWorkspaceSurfaceView+Helpers.swift"]
        )

        XCTAssertTrue(skillIconView.contains("leticon:AppIcon"))
        XCTAssertTrue(skillIconView.contains("self.icon=AppIcon(rawValue:systemName)"))
        XCTAssertTrue(skillIconView.contains("Image(appIcon:icon)"))
        XCTAssertFalse(skillIconView.contains("Image(systemName:systemName)"))

        XCTAssertTrue(settingsMac.contains("Image(appIcon:AppIcon(rawValue:systemImage))"))
        XCTAssertFalse(settingsMac.contains("Image(systemName:systemImage)"))

        XCTAssertTrue(agentWorkspace.contains("Image(appIcon:AppIcon(rawValue:systemImage))"))
        XCTAssertFalse(agentWorkspace.contains("Image(systemName:systemImage)"))
    }

    func testUIKitDynamicIconBoundariesRenderThroughAppIconAdapters() throws {
        let headerActionIcon = try normalizedSource(at: ["sideBar", "Design", "Components", "HeaderActionIcon.swift"])
        let shortcuts = try normalizedSource(at: ["sideBar", "App", "AppLaunchDelegate+Shortcuts.swift"])
        let formattingPopover = try normalizedSource(
            at: ["sideBar", "Views", "Notes", "UIKitNoteFormattingPopoverView.swift"]
        )

        XCTAssertTrue(headerActionIcon.contains("convenienceinit?(appIcon:AppIcon)"))
        XCTAssertTrue(headerActionIcon.contains("self.init(systemName:appIcon.rawValue)"))
        XCTAssertTrue(shortcuts.contains("UIImage(appIcon:AppIcon(rawValue:symbolName))"))
        XCTAssertTrue(formattingPopover.contains("UIImage(appIcon:AppIcon(rawValue:symbol))"))
        XCTAssertFalse(shortcuts.contains("UIImage(systemName:symbolName)"))
        XCTAssertFalse(formattingPopover.contains("UIImage(systemName:symbol)"))
    }

    func testProductionIconRenderingHasNoDirectImageSystemNameBoundaries() throws {
        let forbiddenByFile: [([String], [String])] = [
            (
                ["sideBar", "Views", "Common", "SkillIconView.swift"],
                ["Image(systemName:systemName)"]
            ),
            (
                ["sideBar", "Views", "Settings", "SettingsMacStyles.swift"],
                ["Image(systemName:systemImage)"]
            ),
            (
                ["sideBar", "Views", "AgentWorkspace", "AgentWorkspaceSurfaceView+Helpers.swift"],
                ["Image(systemName:systemImage)"]
            ),
            (
                ["sideBar", "App", "AppLaunchDelegate+Shortcuts.swift"],
                ["UIImage(systemName:symbolName)"]
            ),
            (
                ["sideBar", "Views", "Notes", "UIKitNoteFormattingPopoverView.swift"],
                ["UIImage(systemName:symbol)"]
            )
        ]

        for (path, forbiddenPatterns) in forbiddenByFile {
            let normalized = try normalizedSource(at: path)
            for pattern in forbiddenPatterns {
                XCTAssertFalse(normalized.contains(pattern), "\(path.joined(separator: "/")) still contains \(pattern)")
            }
        }
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
