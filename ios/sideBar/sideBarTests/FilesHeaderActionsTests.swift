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
}
