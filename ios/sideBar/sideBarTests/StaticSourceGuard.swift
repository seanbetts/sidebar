import XCTest

final class StaticSourceGuard: XCTestCase {
    static func normalizedSource(
        at pathComponents: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        try source(at: pathComponents, file: file, line: line)
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }

    static func combinedNormalizedSource(
        at paths: [[String]],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        try paths
            .map { try source(at: $0, file: file, line: line) }
            .joined(separator: "\n")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }

    static func assertFileDoesNotExist(
        at pathComponents: [String],
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let sourceURL = pathComponents.reduce(sideBarRoot(file: file)) { url, component in
            url.appendingPathComponent(component)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path), message, file: file, line: line)
    }

    func testLocalFirstMutationFilesDoNotBranchOnShouldQueueWrites() throws {
        let forbiddenFiles = [
            ["sideBar", "ViewModels", "TasksViewModel+Creation.swift"],
            ["sideBar", "ViewModels", "TasksViewModel+Operations.swift"],
            ["sideBar", "ViewModels", "NotesViewModel.swift"],
            ["sideBar", "ViewModels", "NotesViewModel+EditorSync.swift"],
            ["sideBar", "ViewModels", "IngestionViewModel+Public.swift"],
            ["sideBar", "ViewModels", "WebsitesViewModel.swift"]
        ]

        for file in forbiddenFiles {
            let source = try Self.source(at: file, file: #filePath, line: #line)
            XCTAssertFalse(
                source.contains("shouldQueueWrites"),
                "\(file.joined(separator: "/")) must enqueue local-first writes regardless of reachability"
            )
        }
    }

    private static func source(
        at pathComponents: [String],
        file: StaticString,
        line: UInt
    ) throws -> String {
        let sourceURL = pathComponents.reduce(sideBarRoot(file: file)) { url, component in
            url.appendingPathComponent(component)
        }

        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            XCTFail("Failed to read \(sourceURL.path): \(error)", file: file, line: line)
            throw error
        }
    }

    private static func sideBarRoot(file: StaticString) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
