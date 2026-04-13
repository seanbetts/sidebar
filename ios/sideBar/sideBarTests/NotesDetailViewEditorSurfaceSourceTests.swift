import XCTest

final class NotesDetailViewEditorSurfaceSourceTests: XCTestCase {
    func testSupportedNoteSurfaceUsesTopLeadingZStackAlignment() throws {
        let normalized = try notesDetailViewEditorSurfaceSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(
            normalized.contains("varsupportedNoteSurface:someView{ZStack(alignment:.topLeading){"),
            "Expected the notes read/edit handoff container to pin its children to the top-leading corner."
        )
    }

    func testSupportedNoteSurfaceExpandsToFillAvailableSpace() throws {
        let normalized = try notesDetailViewEditorSurfaceSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(
            normalized.contains(".frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)"),
            "Expected the notes read/edit handoff container to stay stretched to the full note pane during transitions."
        )
    }

    func testConfiguredEditorSurfaceCompletesEditEntryHoldOnMacOS() throws {
        let normalized = try notesDetailViewEditorSurfaceSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(
            normalized.contains(
                "#elseAttributedNoteEditorContainer("
                    + "editorViewModel:editorViewModel,"
                    + "maxContentWidth:contentMaxWidth,"
                    + "onInitialPresentationReady:{"
                    + "editorViewModel.completeEditEntryPresentationHold()"
                    + "},onEscape:handleEscapeKey)"
            ),
            "Expected the macOS editor surface to release the read-surface "
                + "hold only after the AppKit editor reports its first stable "
                + "presentation."
        )
    }
}

private func notesDetailViewEditorSurfaceSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sideBarRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = sideBarRoot
        .appendingPathComponent("sideBar")
        .appendingPathComponent("Views")
        .appendingPathComponent("Notes")
        .appendingPathComponent("NotesDetailView+EditorSurface.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read NotesDetailView+EditorSurface.swift: \(error)", file: file, line: line)
        throw error
    }
}
