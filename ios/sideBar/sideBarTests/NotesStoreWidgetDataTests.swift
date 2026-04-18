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

    func testMakeWidgetDataIncludesAllNotesForScopedFiltering() async {
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
        XCTAssertEqual(snapshot.notes.map(\.path), ["/older.md", "/newer.md"])
        XCTAssertEqual(snapshot.notes.map(\.pinned), [false, false])
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

    func testMakeWidgetDataBuildsFolderScopedPathsWhenTreeUsesIdentifierPaths() async {
        let api = NotesStoreTestsSupport.MockNotesAPI(
            treeResult: .failure(NotesStoreTestsSupport.MockError.forced),
            noteResult: .failure(NotesStoreTestsSupport.MockError.forced)
        )
        let store = NotesStore(api: api, cache: TestCacheClient())
        let tree = FileTree(children: [
            FileNode(
                name: "Personal",
                path: "folder:Personal",
                type: .directory,
                size: nil,
                modified: nil,
                created: nil,
                children: [
                    FileNode(
                        name: "Journal",
                        path: "note-personal-1",
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
                    )
                ],
                expanded: nil,
                pinned: nil,
                pinnedOrder: nil,
                archived: nil,
                folderMarker: nil
            )
        ])

        let snapshot = store.makeWidgetData(from: tree)

        XCTAssertEqual(snapshot.notes.map(\.id), ["note-personal-1"])
        XCTAssertEqual(snapshot.notes.map(\.path), ["note-personal-1"])
        XCTAssertEqual(snapshot.notes.map(\.scopePath), ["/Personal/note-personal-1"])
    }
}
