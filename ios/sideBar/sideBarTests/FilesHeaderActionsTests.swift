import Foundation
import XCTest
@testable import sideBar

final class FilesHeaderActionsTests: XCTestCase {
    func testMakeTemporaryShareURLStoresDataUsingProvidedFilename() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let temporaryStore = TemporaryFileStore(directory: directory)
        let data = Data("shared file".utf8)

        let url = try FileShareAction.makeTemporaryShareURL(
            data: data,
            filename: "Quarterly Report.pdf",
            temporaryStore: temporaryStore
        )

        XCTAssertEqual(url.lastPathComponent.hasSuffix("Quarterly Report.pdf"), true)
        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    func testFileHeaderMenuUsesShareFactoryInsteadOfInlineMenuItem() throws {
        let source = try filesHeaderActionsSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(source.contains(".shareFile{Task{awaitshareFile()}}"))
        XCTAssertFalse(source.contains("SidebarMenuItem(title:\"Share\""))
    }
}

private func filesHeaderActionsSource(
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
        .appendingPathComponent("Files")
        .appendingPathComponent("FilesHeaderActions.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read FilesHeaderActions.swift: \(error)", file: file, line: line)
        throw error
    }
}
