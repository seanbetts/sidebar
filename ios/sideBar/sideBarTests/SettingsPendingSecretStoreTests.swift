import Foundation
import XCTest
@testable import sideBar

final class SettingsPendingSecretStoreTests: XCTestCase {
    func testStageLookupAndDeleteByReference() throws {
        let store = SettingsPendingSecretStore()
        let reference = try store.stage(Data("provider-key".utf8))

        XCTAssertEqual(try store.lookup(reference: reference), Data("provider-key".utf8))

        try store.delete(reference: reference)

        XCTAssertThrowsError(try store.lookup(reference: reference))
    }
}
