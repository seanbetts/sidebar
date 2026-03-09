import XCTest
@testable import sideBar

final class TestIsolationTests: XCTestCase {
    func testUserDefaultsSuitesAreUniquePerAllocation() {
        let first = TestIsolation.makeUserDefaults(prefix: "TestIsolationTests")
        let second = TestIsolation.makeUserDefaults(prefix: "TestIsolationTests")
        defer {
            first.tearDown()
            second.tearDown()
        }

        XCTAssertNotEqual(first.suiteName, second.suiteName)
        first.defaults.set("first", forKey: "value")
        second.defaults.set("second", forKey: "value")

        XCTAssertEqual(first.defaults.string(forKey: "value"), "first")
        XCTAssertEqual(second.defaults.string(forKey: "value"), "second")
    }

    func testTemporaryDirectoriesAreUniquePerAllocation() throws {
        let first = try TestIsolation.makeTemporaryDirectory(prefix: "TestIsolationTests")
        let second = try TestIsolation.makeTemporaryDirectory(prefix: "TestIsolationTests")
        defer {
            first.tearDown()
            second.tearDown()
        }

        XCTAssertNotEqual(first.url, second.url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.url.path))
    }
}
