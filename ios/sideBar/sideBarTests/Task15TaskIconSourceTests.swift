import XCTest

final class Task15TaskIconSourceTests: XCTestCase {
    func testTaskFeatureActionStatusIconsUseAppIconVocabulary() throws {
        try assertNoForbiddenIconPatterns([
            (
                ["sideBar", "Views", "Tasks", "TasksViewComponents.swift"],
                [
                    "Image(systemName:\"checkmark\")",
                    "Image(systemName:\"circle\")",
                    "Image(systemName:\"text.document\")",
                    "Image(systemName:\"exclamationmark.circle\")",
                    "TaskPill(text:\"Overdue\",iconName:\"exclamationmark.circle\")",
                    "Image(systemName:\"trash\")",
                    "Image(systemName:\"ellipsis\")",
                    "Image(systemName:\"folder\")"
                ]
            ),
            (
                ["sideBar", "Views", "Tasks", "TasksDetailView.swift"],
                [
                    "systemName:\"plus\"",
                    "Label(\"Notasksdue\",systemImage:\"checkmark.circle\")",
                    "Image(systemName:\"checkmark\")"
                ]
            ),
            (
                ["sideBar", "Views", "Tasks", "TasksDetailView+FloatingDock.swift"],
                ["systemName:\"plus\""]
            ),
            (
                ["sideBar", "Views", "Tasks", "TasksModals.swift"],
                ["Image(systemName:\"xmark.circle.fill\")"]
            ),
            (
                ["sideBar", "Views", "Tasks", "TasksModals+Scheduling.swift"],
                [
                    "Image(systemName:\"xmark.circle.fill\")",
                    "Image(systemName:\"checkmark\")"
                ]
            ),
            (
                ["sideBar", "Views", "SidebarPanels", "TasksPanelRows.swift"],
                ["Image(systemName:\"checkmark\")"]
            )
        ])

        let taskRows = try source(at: ["sideBar", "Views", "Tasks", "TasksViewComponents.swift"])
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        XCTAssertTrue(taskRows.contains("TaskPill(text:\"Overdue\",icon:AppIcon.State.error)"))
        XCTAssertTrue(taskRows.contains("Image(appIcon:AppIcon.Action.delete)"))
        XCTAssertTrue(taskRows.contains("Image(appIcon:AppIcon.Action.more)"))
        XCTAssertTrue(taskRows.contains("Image(appIcon:AppIcon.Content.folder)"))

        let taskDetail = try source(at: ["sideBar", "Views", "Tasks", "TasksDetailView.swift"])
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        XCTAssertTrue(taskDetail.contains("HeaderActionButton(icon:AppIcon.Action.add"))
        XCTAssertTrue(taskDetail.contains("Image(appIcon:AppIcon.State.success)"))
    }

    private func assertNoForbiddenIconPatterns(
        _ forbiddenByFile: [([String], [String])],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        for (path, forbiddenPatterns) in forbiddenByFile {
            let normalized = try source(at: path)
                .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            for pattern in forbiddenPatterns {
                XCTAssertFalse(
                    normalized.contains(pattern),
                    "\(path.joined(separator: "/")) still contains \(pattern)",
                    file: file,
                    line: line
                )
            }
        }
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
