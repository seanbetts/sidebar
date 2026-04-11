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

    func testScratchpadPhoneSheetUsesNativeSheetSurfaceWithoutInnerGlassCard() throws {
        let normalized = try normalizedPhoneSheetContentSource()

        XCTAssertFalse(normalized.contains("ScratchpadHeaderRow("))
        XCTAssertFalse(normalized.contains(".glassChrome("))
        XCTAssertTrue(normalized.contains("ScratchpadErrorBannerView(errorMessage:errorMessage)"))
        XCTAssertTrue(normalized.contains("Text(\"Saving...\")"))
    }

    func testScratchpadPopoverSurfaceUsesNativePopoverOnIOSAndSharedShellOnMacOS() throws {
        let normalized = try normalizedScratchpadPopoverSource()

        XCTAssertTrue(normalized.contains("structScratchpadPopoverSurface:View{"))
        XCTAssertTrue(normalized.contains("#ifos(macOS)"))
        XCTAssertTrue(normalized.contains("MacPopoverShell(type:scratchpadPopoverPanelType())"))
        XCTAssertTrue(normalized.contains("ScratchpadPopoverView("))
        XCTAssertTrue(normalized.contains("scratchpadView.padding(Self.iPadPopoverPadding)"))
        XCTAssertTrue(normalized.contains("frame(minWidth:Self.iPadPopoverWidth,idealWidth:Self.iPadPopoverWidth,maxWidth:Self.iPadPopoverWidth,alignment:.topLeading)"))
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

private func normalizedPhoneSheetContentSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let source = try scratchpadPopoverSource(file: file, line: line)
    guard let start = source.range(of: "private var phoneSheetContent: some View {"),
          let end = source.range(of: "@ViewBuilder\n    private var phoneScratchpadBody", range: start.upperBound..<source.endIndex) else {
        XCTFail("Failed to isolate phoneSheetContent in ScratchpadPopoverView.swift", file: file, line: line)
        return ""
    }

    return String(source[start.lowerBound..<end.lowerBound])
        .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
}
