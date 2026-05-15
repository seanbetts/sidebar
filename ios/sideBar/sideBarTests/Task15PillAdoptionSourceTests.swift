import XCTest

final class Task15PillAdoptionSourceTests: XCTestCase {
    func testTaskPillDelegatesVisualChromeToMetadataPill() throws {
        let normalized = try source(at: ["sideBar", "Views", "Tasks", "TasksViewComponents.swift"])
            .normalizedForTask15PillAssertions()
        let taskPill = try segment(
            in: normalized,
            from: "structTaskPill:View{",
            to: "structTaskRow<MenuContent:View>:View{"
        )

        XCTAssertTrue(taskPill.contains("MetadataPill(text"))
        XCTAssertFalse(taskPill.contains("Capsule()"))
        XCTAssertFalse(taskPill.contains(".clipShape(Capsule())"))
        XCTAssertFalse(taskPill.contains(".background(pillBackground)"))
    }

    func testChatMessageRolePillDelegatesVisualChromeToMetadataPill() throws {
        let normalized = try source(at: ["sideBar", "Views", "Chat", "ChatMessageRow.swift"])
            .normalizedForTask15PillAssertions()

        XCTAssertTrue(normalized.contains("MetadataPill(message.role==.assistant?assistantDisplayName:\"You\")"))
        XCTAssertFalse(normalized.contains("privatevarrolePillBackground:Color"))
        XCTAssertFalse(normalized.contains("privatevarrolePillText:Color"))
        XCTAssertFalse(normalized.contains("privatevarrolePillBorder:someView"))
        XCTAssertFalse(normalized.contains(".clipShape(Capsule())"))
    }

    func testChatToolSummaryPillDelegatesVisualChromeToMetadataPill() throws {
        let normalized = try source(at: ["sideBar", "Views", "Chat", "ChatToolComponents.swift"])
            .normalizedForTask15PillAssertions()

        XCTAssertTrue(normalized.contains("MetadataPill(text,maxTitleWidth:maxToolPillTextWidth)"))
        XCTAssertFalse(normalized.contains("Capsule(style:.continuous)"))
        XCTAssertFalse(normalized.contains("privatevartoolPillBackground:Color"))
        XCTAssertFalse(normalized.contains("privatevartoolPillBorder:someView"))
    }

    func testResolvedStatusPillSurfacesStayOnSharedStatusPill() throws {
        let siteHeader = try source(at: ["sideBar", "Views", "Websites", "SiteHeaderBar.swift"])
            .normalizedForTask15PillAssertions()
        let toastCenter = try source(at: ["sideBar", "Design", "Components", "ToastCenter.swift"])
            .normalizedForTask15PillAssertions()

        XCTAssertTrue(siteHeader.contains("HeaderStatusPillButton("))
        XCTAssertTrue(toastCenter.contains("StatusPill("))
    }

    private func segment(
        in source: String,
        from startMarker: String,
        to endMarker: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        guard let start = source.range(of: startMarker)?.lowerBound,
              let end = source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound else {
            XCTFail("Failed to find source segment from \(startMarker) to \(endMarker)", file: file, line: line)
            throw NSError(domain: "Task15PillAdoptionSourceTests", code: 1)
        }
        return String(source[start..<end])
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

private extension String {
    func normalizedForTask15PillAssertions() -> String {
        replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }
}
