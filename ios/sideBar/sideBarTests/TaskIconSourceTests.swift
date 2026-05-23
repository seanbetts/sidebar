import XCTest

final class TaskIconSourceTests: XCTestCase {
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

    func testTaskTaxonomyAndRecurrenceIconsUseAppIconVocabulary() throws {
        try assertNoForbiddenIconPatterns([
            (
                ["sideBar", "Views", "SidebarPanels", "TasksPanel.swift"],
                [
                    "iconName:\"calendar\"",
                    "iconName:\"calendar.badge.clock\"",
                    "iconName:\"calendar.badge.checkmark\"",
                    "iconName:\"square.3.layers.3d\"",
                    "iconName:\"list.bullet\""
                ]
            ),
            (
                ["sideBar", "Views", "SidebarPanels", "TasksPanelRows.swift"],
                ["Image(systemName:iconName)"]
            ),
            (
                ["sideBar", "ViewModels", "TasksViewModel.swift"],
                [
                    "titleIcon=\"checkmark.square\"",
                    "titleIcon=\"calendar\"",
                    "titleIcon=\"calendar.badge.clock\"",
                    "titleIcon=\"calendar.badge.checkmark\"",
                    "titleIcon=\"square.3.layers.3d\"",
                    "titleIcon=\"list.bullet\"",
                    "titleIcon=\"magnifyingglass\""
                ]
            ),
            (
                ["sideBar", "Views", "Tasks", "TasksDetailView+EmptyState.swift"],
                ["systemImage:\"calendar\""]
            ),
            (
                ["sideBar", "Views", "Tasks", "TasksDetailView.swift"],
                [
                    "Image(systemName:state.titleIcon)",
                    "iconName:\"calendar\"",
                    "iconName=\"list.bullet\"",
                    "iconName=\"square.3.layers.3d\"",
                    "Image(systemName:iconName)"
                ]
            ),
            (
                ["sideBar", "Views", "Tasks", "TasksViewComponents.swift"],
                ["Image(systemName:\"repeat\")"]
            )
        ])

        let appIcon = try source(at: ["sideBarShared", "Utilities", "AppIcon.swift"])
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        XCTAssertTrue(appIcon.contains("enumTasks"))
        XCTAssertTrue(appIcon.contains("publicstaticlettoday=AppIcon(rawValue:\"calendar\")"))
        XCTAssertTrue(appIcon.contains("publicstaticletupcoming=AppIcon(rawValue:\"calendar.badge.clock\")"))
        XCTAssertTrue(appIcon.contains("publicstaticletcompleted=AppIcon(rawValue:\"calendar.badge.checkmark\")"))
        XCTAssertTrue(appIcon.contains("publicstaticletgroup=AppIcon(rawValue:\"square.3.layers.3d\")"))
        XCTAssertTrue(appIcon.contains("publicstaticletproject=AppIcon(rawValue:\"list.bullet\")"))
        XCTAssertTrue(appIcon.contains("publicstaticletrecurrence=AppIcon(rawValue:\"repeat\")"))

        let detailState = try source(at: ["sideBar", "ViewModels", "TasksViewModel+ViewState.swift"])
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        XCTAssertTrue(detailState.contains("publiclettitleIcon:AppIcon"))

        let taskRows = try source(at: ["sideBar", "Views", "SidebarPanels", "TasksPanelRows.swift"])
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        XCTAssertTrue(taskRows.contains("leticon:AppIcon"))
        XCTAssertTrue(taskRows.contains("Image(appIcon:icon)"))

        let taskDetail = try source(at: ["sideBar", "Views", "Tasks", "TasksDetailView.swift"])
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        XCTAssertTrue(taskDetail.contains("Image(appIcon:state.titleIcon)"))
        XCTAssertTrue(taskDetail.contains("icon:AppIcon.Tasks.today"))
        XCTAssertTrue(taskDetail.contains("icon=AppIcon.Tasks.project"))
        XCTAssertTrue(taskDetail.contains("AppIcon.Tasks.group"))
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
