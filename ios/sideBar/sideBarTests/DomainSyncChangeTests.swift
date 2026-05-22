import XCTest
@testable import sideBar

@MainActor
final class DomainSyncChangeTests: XCTestCase {
    func testChangeBuildsRefreshTargetsForListAndDetail() {
        let change = DomainSyncChange(
            section: .files,
            entityId: "file-1",
            kind: .detailRefresh,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            requiresListRefresh: true,
            requiresDetailRefresh: true,
            canPatchMetadata: false
        )

        XCTAssertEqual(change.refreshTargets, [.sectionList(.files), .visibleDetail(.files)])
    }

    func testMetadataPatchOnlyChangeDoesNotRequireRefreshTargets() {
        let change = DomainSyncChange(
            section: .tasks,
            entityId: "task-1",
            kind: .metadataPatch,
            updatedAt: nil,
            requiresListRefresh: false,
            requiresDetailRefresh: false,
            canPatchMetadata: true
        )

        XCTAssertEqual(change.refreshTargets, [])
    }

    func testArchiveRefreshAddsArchiveListTarget() {
        let change = DomainSyncChange(
            section: .websites,
            entityId: nil,
            kind: .archiveRefresh,
            updatedAt: nil,
            requiresListRefresh: false,
            requiresDetailRefresh: false,
            canPatchMetadata: false
        )

        XCTAssertEqual(change.refreshTargets, [.archiveList(.websites)])
    }
}
