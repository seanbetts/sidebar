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

    func testNoteDeletedEventRequestsClosingOpenNoteInWorkspace() async {
        let cache = TestCacheClient()
        let api = ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([]))
        var requestedClosedNoteID: String?
        let viewModel = makeViewModel(
            api: api,
            cache: cache,
            onCloseNoteRequested: { noteID in
                requestedClosedNoteID = noteID
                return true
            }
        )

        viewModel.handle(event: ChatStreamEvent(
            type: .entityDeleted,
            data: AnyCodable([
                "entity_type": "note",
                "entity_id": "note-1",
                "invalidate": ["notes", "note:note-1"]
            ])
        ))

        XCTAssertEqual(requestedClosedNoteID, "note-1")
    }

    func testSuccessfulUndoReopensNoteClosedByDeletion() async {
        let cache = TestCacheClient()
        let api = ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([]))
        var requestedOpenNoteID: String?
        let viewModel = makeViewModel(
            api: api,
            cache: cache,
            onOpenNoteRequested: { requestedOpenNoteID = $0 },
            onCloseNoteRequested: { _ in true }
        )

        viewModel.handle(event: ChatStreamEvent(
            type: .entityDeleted,
            data: AnyCodable([
                "entity_type": "note",
                "entity_id": "note-1",
                "invalidate": ["notes", "note:note-1"]
            ])
        ))
        viewModel.handleSuccessfulUndo(ChatToolAction(
            id: "undo-1",
            kind: .undo,
            summary: "Undo note deletion?",
            toolName: nil,
            guardReason: nil,
            undoSupported: false,
            expiresAt: nil,
            entityType: "note",
            entityId: "note-1",
            status: .pending
        ))

        XCTAssertEqual(requestedOpenNoteID, "note-1")
    }

    func testSuccessfulUndoDoesNotReopenNoteWhenDeletionDidNotCloseIt() async {
        let cache = TestCacheClient()
        let api = ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([]))
        var requestedOpenNoteID: String?
        let viewModel = makeViewModel(
            api: api,
            cache: cache,
            onOpenNoteRequested: { requestedOpenNoteID = $0 },
            onCloseNoteRequested: { _ in false }
        )

        viewModel.handle(event: ChatStreamEvent(
            type: .entityDeleted,
            data: AnyCodable([
                "entity_type": "note",
                "entity_id": "note-1",
                "invalidate": ["notes", "note:note-1"]
            ])
        ))
        viewModel.handleSuccessfulUndo(ChatToolAction(
            id: "undo-1",
            kind: .undo,
            summary: "Undo note deletion?",
            toolName: nil,
            guardReason: nil,
            undoSupported: false,
            expiresAt: nil,
            entityType: "note",
            entityId: "note-1",
            status: .pending
        ))

        XCTAssertNil(requestedOpenNoteID)
    }

    func testWorkspacePatchOpenEntityDispatchesGenericWorkspaceOpenRequest() async {
        let cache = TestCacheClient()
        let api = ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([]))
        var dispatchedActions: [WorkspaceAction] = []
        let viewModel = makeViewModel(
            api: api,
            cache: cache,
            workspaceActionDispatcher: { action in
                dispatchedActions.append(action)
            }
        )

        viewModel.handle(event: ChatStreamEvent(
            type: .workspacePatch,
            data: AnyCodable([
                "version": 1,
                "operations": [
                    [
                        "op": "open_entity",
                        "entity": [
                            "type": "note",
                            "id": "note-1",
                            "title": "Orion — Project Brief"
                        ],
                        "route_url": "sidebar://notes/note-1",
                        "section": "notes",
                        "pane": "primary"
                    ]
                ]
            ])
        ))

        XCTAssertEqual(dispatchedActions.count, 1)
        guard case .openEntity(let request) = dispatchedActions.first else {
            return XCTFail("Expected open entity action")
        }
        XCTAssertEqual(request.entity.type, "note")
        XCTAssertEqual(request.entity.id, "note-1")
        XCTAssertEqual(request.entity.title, "Orion — Project Brief")
        XCTAssertEqual(request.routeURL?.absoluteString, "sidebar://notes/note-1")
        XCTAssertEqual(request.section, .notes)
        XCTAssertEqual(request.pane, .primary)
    }
}
