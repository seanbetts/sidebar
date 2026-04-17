import Foundation
import XCTest
@testable import sideBar

@MainActor
final class NotesStoreRefreshMergeTests: XCTestCase {
    func testApplyTreeUpdateSyncsActiveNoteMetadataWithoutDroppingContent() async {
        let cache = TestCacheClient()
        let api = NotesStoreTestsSupport.MockNotesAPI(
            treeResult: .failure(NotesStoreTestsSupport.MockError.forced),
            noteResult: .failure(NotesStoreTestsSupport.MockError.forced)
        )
        let store = NotesStore(api: api, cache: cache)
        let activeNote = NotePayload(
            id: "note-1",
            name: "Cached.md",
            content: "Preserve this note body",
            path: "/note-1.md",
            modified: 1,
            created: nil
        )
        store.applyEditorUpdate(activeNote)

        let refreshedTree = FileTree(children: [
            FileNode(
                name: "Fresh.md",
                path: "/note-1.md",
                type: .file,
                size: nil,
                modified: 2,
                created: nil,
                children: nil,
                expanded: nil,
                pinned: nil,
                pinnedOrder: nil,
                archived: nil,
                folderMarker: nil
            )
        ])

        store.applyTreeUpdate(refreshedTree, persist: true)

        XCTAssertEqual(store.activeNote?.name, "Fresh.md")
        XCTAssertEqual(store.activeNote?.modified, 2)
        XCTAssertEqual(store.activeNote?.plainText, "Preserve this note body")

        let cached: NotePayload? = cache.get(key: CacheKeys.note(id: "note-1"))
        XCTAssertEqual(cached?.name, "Fresh.md")
        XCTAssertEqual(cached?.plainText, "Preserve this note body")
    }
}
