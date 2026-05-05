import XCTest
import sideBarShared
@testable import sideBar

final class DesignQuickGapSourceTests: XCTestCase {
    func testWarningTokensUseAmberPalette() throws {
        let source = try sideBarSource("Design/DesignTokens.swift")

        XCTAssertTrue(source.contains("Color(red: 0.85, green: 0.47, blue: 0.02)"))
        XCTAssertTrue(source.contains("Color(red: 0.98, green: 0.75, blue: 0.14)"))
        XCTAssertFalse(source.contains("static let warning = textSecondary"))
        XCTAssertFalse(source.contains("static let warningBackground = muted.opacity"))
    }

    func testSizeTokensIncludeSharedChromeWidths() throws {
        let source = try sideBarSource("Design/DesignTokens.swift")

        XCTAssertTrue(source.contains("static let railWidth: CGFloat = 56"))
        XCTAssertTrue(source.contains("static let dividerWidth: CGFloat = 8"))
        XCTAssertTrue(source.contains("static let rightSidebarDefaultWidth: CGFloat = 360"))
        XCTAssertTrue(source.contains("static let inspectorMaxWidth: CGFloat = 1_120"))
    }

    func testLegacyTypographyNamespaceIsRemoved() throws {
        let source = try sideBarSource("Design/DesignTokens.swift")

        XCTAssertFalse(source.contains("enum Typography"))
    }

    func testPlatformTokensPanelHeaderAliasIsRemoved() throws {
        let source = try sideBarSource("Design/PlatformTokens.swift")
        let panelComponents = try sideBarSource("Views/SidebarPanels/PanelComponents.swift")
        let topSafeArea = try sideBarSource("Views/ContentView+TopSafeArea.swift")

        XCTAssertFalse(source.contains("panelHeaderBackground"))
        XCTAssertFalse(panelComponents.contains("PlatformTokens.panelHeaderBackground"))
        XCTAssertFalse(topSafeArea.contains("PlatformTokens.panelHeaderBackground"))
    }

    func testDeadSwiftUINoteEditorSurfaceFileIsRemoved() {
        XCTAssertFalse(sideBarFileExists("Views/Notes/SwiftUINoteTextEditorSurface.swift"))
    }

    func testNotesTreeRowsHaveRowLevelAccessibilityLabel() throws {
        let normalized = try sideBarSource("Views/SidebarPanels/NotesPanelComponents.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains(".accessibilityLabel(notesTreeRowAccessibilityLabel(for:item))"))
        let noteItem = FileNodeItem(id: "note-1", name: "Planning", type: .file, created: 1_704_067_200)
        XCTAssertEqual(
            notesTreeRowAccessibilityLabel(for: noteItem),
            "Planning, note, created \(noteItem.formattedCreatedDate ?? "")"
        )
        XCTAssertEqual(
            notesTreeRowAccessibilityLabel(
                for: FileNodeItem(id: "folder-1", name: "Projects", type: .directory, children: [])
            ),
            "Projects, folder"
        )
    }
}

private func sideBarSource(
    _ relativePath: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let sourceURL = sideBarRootURL(file: file)
        .appendingPathComponent("sideBar")
        .appendingPathComponent(relativePath)

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read \(relativePath): \(error)", file: file, line: line)
        throw error
    }
}

private func sideBarFileExists(
    _ relativePath: String,
    file: StaticString = #filePath
) -> Bool {
    let sourceURL = sideBarRootURL(file: file)
        .appendingPathComponent("sideBar")
        .appendingPathComponent(relativePath)
    return FileManager.default.fileExists(atPath: sourceURL.path)
}

private func sideBarRootURL(file: StaticString) -> URL {
    URL(fileURLWithPath: "\(file)")
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
