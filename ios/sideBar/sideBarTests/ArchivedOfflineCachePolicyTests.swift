import XCTest
@testable import sideBar

final class ArchivedOfflineCachePolicyTests: XCTestCase {
    func testArchiveOfflinePolicyUsesSharedBoundsAcrossNativeSurfaces() {
        XCTAssertEqual(ArchivedOfflineCachePolicy.detailRetentionDays, 7)
        XCTAssertEqual(ArchivedOfflineCachePolicy.detailPrefetchLimit, 50)
        XCTAssertEqual(ArchivedOfflineCachePolicy.listLimit, 500)
    }

    func testNotesAndWebsitesStoresReferenceSharedArchivePolicyConstants() throws {
        let notesSource = try source(at: ["sideBar", "Stores", "NotesStore.swift"])
        let websitesSource = try source(at: ["sideBar", "Stores", "WebsitesStore.swift"])
        let combined = notesSource + "\n" + websitesSource

        XCTAssertEqual(combined.matches(of: "ArchivedOfflineCachePolicy.detailRetentionDays"), 2)
        XCTAssertEqual(combined.matches(of: "ArchivedOfflineCachePolicy.detailPrefetchLimit"), 2)
        XCTAssertEqual(combined.matches(of: "ArchivedOfflineCachePolicy.listLimit"), 2)
    }
}

private extension String {
    func matches(of pattern: String) -> Int {
        components(separatedBy: pattern).count - 1
    }
}

private func source(
    at pathComponents: [String],
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let root = URL(fileURLWithPath: "\(file)")
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let url = pathComponents.reduce(root) { partial, component in
        partial.appendingPathComponent(component)
    }
    do {
        return try String(contentsOf: url, encoding: .utf8)
    } catch {
        XCTFail("Failed to read \(url.path): \(error)", file: file, line: line)
        throw error
    }
}
