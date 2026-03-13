import Foundation
import sideBarShared
import XCTest
@testable import sideBar

@MainActor
final class NotesStoreWidgetDataTests: XCTestCase {
    private func makeWidgetDataManager() -> WidgetDataManager {
        WidgetDataManager(
            userDefaults: UserDefaults(
                suiteName: "NotesStoreWidgetDataTests.\(UUID().uuidString)"
            )!
        )
    }

    func testUpdateWidgetDataFallsBackToRecentNotesWhenNoPinnedNotes() async {
        let api = NotesStoreTestsSupport.MockNotesAPI(
            treeResult: .failure(NotesStoreTestsSupport.MockError.forced),
            noteResult: .failure(NotesStoreTestsSupport.MockError.forced)
        )
        let store = NotesStore(api: api, cache: TestCacheClient())
        let tree = FileTree(children: [
            FileNode(
                name: "Older.md",
                path: "/older.md",
                type: .file,
                size: nil,
                modified: 1,
                created: nil,
                children: nil,
                expanded: nil,
                pinned: false,
                pinnedOrder: nil,
                archived: nil,
                folderMarker: nil
            ),
            FileNode(
                name: "Newer.md",
                path: "/newer.md",
                type: .file,
                size: nil,
                modified: 2,
                created: nil,
                children: nil,
                expanded: nil,
                pinned: false,
                pinnedOrder: nil,
                archived: nil,
                folderMarker: nil
            )
        ])

        let snapshot = store.makeWidgetData(from: tree)

        XCTAssertEqual(snapshot.totalCount, 2)
        XCTAssertEqual(snapshot.notes.map(\.path), ["/newer.md", "/older.md"])
    }

    func testUpdateWidgetDataPrefersPinnedNotesButFillsWithRecentUnpinnedNotes() async {
        let api = NotesStoreTestsSupport.MockNotesAPI(
            treeResult: .failure(NotesStoreTestsSupport.MockError.forced),
            noteResult: .failure(NotesStoreTestsSupport.MockError.forced)
        )
        let store = NotesStore(api: api, cache: TestCacheClient())
        let tree = FileTree(children: [
            FileNode(
                name: "Pinned.md",
                path: "/pinned.md",
                type: .file,
                size: nil,
                modified: 1,
                created: nil,
                children: nil,
                expanded: nil,
                pinned: true,
                pinnedOrder: 0,
                archived: nil,
                folderMarker: nil
            ),
            FileNode(
                name: "Recent.md",
                path: "/recent.md",
                type: .file,
                size: nil,
                modified: 2,
                created: nil,
                children: nil,
                expanded: nil,
                pinned: false,
                pinnedOrder: nil,
                archived: nil,
                folderMarker: nil
            )
        ])

        let snapshot = store.makeWidgetData(from: tree)

        XCTAssertEqual(snapshot.totalCount, 2)
        XCTAssertEqual(snapshot.notes.map(\.path), ["/pinned.md", "/recent.md"])
    }

    func testApplyTreeUpdateRepairsWidgetSnapshotEvenWhenTreeIsUnchanged() async {
        let api = NotesStoreTestsSupport.MockNotesAPI(
            treeResult: .failure(NotesStoreTestsSupport.MockError.forced),
            noteResult: .failure(NotesStoreTestsSupport.MockError.forced)
        )
        let widgetDataManager = makeWidgetDataManager()
        let store = NotesStore(
            api: api,
            cache: TestCacheClient(),
            widgetDataManager: widgetDataManager
        )
        let tree = FileTree(children: [
            FileNode(
                name: "Pinned.md",
                path: "/pinned.md",
                type: .file,
                size: nil,
                modified: 1,
                created: nil,
                children: nil,
                expanded: nil,
                pinned: true,
                pinnedOrder: 0,
                archived: nil,
                folderMarker: nil
            )
        ])

        store.applyTreeUpdate(tree, persist: false)
        widgetDataManager.store(WidgetNoteData.empty, for: .notes)

        store.applyTreeUpdate(tree, persist: false)

        let snapshot: WidgetNoteData = widgetDataManager.load(for: .notes)
        XCTAssertEqual(snapshot.totalCount, 1)
        XCTAssertEqual(snapshot.notes.map(\.path), ["/pinned.md"])
    }
}
