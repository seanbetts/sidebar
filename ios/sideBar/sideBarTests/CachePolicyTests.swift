import XCTest
@testable import sideBar

final class CachePolicyTests: XCTestCase {
    func testCachePoliciesArePositive() {
        let policies: [TimeInterval] = [
            CachePolicy.conversationsList,
            CachePolicy.conversationDetail,
            CachePolicy.notesTree,
            CachePolicy.noteContent,
            CachePolicy.websitesList,
            CachePolicy.websiteDetail,
            CachePolicy.memoriesList,
            CachePolicy.ingestionList,
            CachePolicy.ingestionMeta,
            CachePolicy.scratchpad,
            CachePolicy.filesTree,
            CachePolicy.fileContent,
            CachePolicy.userSettings,
            CachePolicy.skillsList,
            CachePolicy.profileImage
        ]

        XCTAssertTrue(policies.allSatisfy { $0 > 0 })
    }
}
