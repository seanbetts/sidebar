import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class ChatViewModelWorkspaceOpeningTests: ChatViewModelTestCase {
    func testNoteCreatedEventRequestsOpeningCreatedNoteInWorkspace() async {
        let cache = TestCacheClient()
        let api = ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([]))
        var requestedNoteID: String?
        let viewModel = makeViewModel(
            api: api,
            cache: cache,
            onOpenNoteRequested: { requestedNoteID = $0 }
        )

        viewModel.handle(event: ChatStreamEvent(
            type: .entityChanged,
            data: AnyCodable([
                "entity_type": "note",
                "entity_id": "note-1",
                "change": "created",
                "patch": [
                    "id": "note-1",
                    "path": "Folder/Test.md",
                    "open_in_workspace": true
                ],
                "invalidate": ["notes", "note:note-1"]
            ])
        ))

        XCTAssertEqual(requestedNoteID, "note-1")
    }

    func testNoteOpenedEventRequestsOpeningExistingNoteInWorkspace() async {
        let cache = TestCacheClient()
        let api = ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([]))
        var requestedNoteID: String?
        let viewModel = makeViewModel(
            api: api,
            cache: cache,
            onOpenNoteRequested: { requestedNoteID = $0 }
        )

        viewModel.handle(event: ChatStreamEvent(
            type: .entityChanged,
            data: AnyCodable([
                "entity_type": "note",
                "entity_id": "note-1",
                "change": "opened",
                "patch": [
                    "id": "note-1",
                    "path": "Folder/Test.md",
                    "open_in_workspace": true
                ],
                "invalidate": ["notes", "note:note-1"]
            ])
        ))

        XCTAssertEqual(requestedNoteID, "note-1")
    }
}
