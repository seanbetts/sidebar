import XCTest

func attributedNoteEditorContainerSource(
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
        .appendingPathComponent("AttributedNoteEditorContainer.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read AttributedNoteEditorContainer.swift: \(error)", file: file, line: line)
        throw error
    }
}

func attributedNoteEditorContainerMountsSwiftUISurfaceDirectly(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> Bool {
    let normalized = try attributedNoteEditorContainerSource(file: file, line: line)
        .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

    return normalized.contains("privatevareditorSurface:someView{SwiftUINoteTextEditorSurface(")
}
