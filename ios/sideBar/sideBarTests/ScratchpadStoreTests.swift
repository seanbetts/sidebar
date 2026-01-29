import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class ScratchpadStoreTests: XCTestCase {
    func testBumpIncrementsVersion() {
        let store = ScratchpadStore()
        XCTAssertEqual(store.version, 0)

        store.bump()

        XCTAssertEqual(store.version, 1)
    }
}
