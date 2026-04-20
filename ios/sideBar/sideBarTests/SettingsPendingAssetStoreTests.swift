import Foundation
import XCTest
@testable import sideBar

final class SettingsPendingAssetStoreTests: XCTestCase {
    func testStageLookupAndDeleteProfileImageAsset() throws {
        let store = SettingsPendingAssetStore(fileManager: FileManager.default)
        let reference = try store.stageProfileImage(
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            contentType: "image/png",
            filename: "profile.png"
        )

        let asset = try store.lookup(reference: reference)

        XCTAssertEqual(asset.data, Data([0x89, 0x50, 0x4E, 0x47]))
        XCTAssertEqual(asset.contentType, "image/png")
        XCTAssertEqual(asset.filename, "profile.png")

        try store.delete(reference: reference)

        XCTAssertThrowsError(try store.lookup(reference: reference))
    }
}
