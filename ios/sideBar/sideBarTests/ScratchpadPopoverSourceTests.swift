import XCTest

final class ScratchpadPopoverSourceTests: XCTestCase {
    func testScratchpadReadStateUsesEmptyStateView() throws {
        let normalized = try normalizedScratchpadPopoverSource()

        XCTAssertTrue(
            normalized.contains(
                "EmptyStateView(title:\"Scratchpadisempty.\",subtitle:ScratchpadConstants.placeholder,systemImage:\"square.and.pencil\")"
            )
        )
        XCTAssertFalse(normalized.contains("Text(draft.isEmpty?ScratchpadConstants.placeholder:draft)"))
    }

    func testScratchpadPhoneSheetUsesSharedEmptyStateInsteadOfInlinePlaceholder() throws {
        let normalized = try normalizedScratchpadPopoverSource()

        XCTAssertFalse(normalized.contains("ifdraft.isEmpty{Text(ScratchpadConstants.placeholder)"))
        XCTAssertTrue(
            normalized.contains("ifdraft.isEmpty&&!isEditing{scratchpadEmptyState{beginEditing()}}")
        )
        XCTAssertTrue(
            normalized.contains("}elseifdraft.isEmpty{scratchpadEmptyState{beginEditing()}}")
        )
    }

    func testScratchpadPhoneSheetDoesNotForceEditingBeforeContentLoads() throws {
        let normalized = try normalizedScratchpadPopoverSource()

        XCTAssertFalse(normalized.contains("ifusesPhoneSheetLayout{isEditing=trueisEditorFocused=true}"))
    }
}

private func normalizedScratchpadPopoverSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    try scratchpadPopoverSource(file: file, line: line)
        .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
}

private func scratchpadPopoverSource(
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
        .appendingPathComponent("ScratchpadPopoverView.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read ScratchpadPopoverView.swift: \(error)", file: file, line: line)
        throw error
    }
}
