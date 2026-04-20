import XCTest

final class ChatStreamSyncSourceTests: XCTestCase {
    func testChatRealtimeHelpersDoNotKeepDeadChatSpecificSyncHandlers() throws {
        let source = try String(
            contentsOfFile: "/Users/sean/Coding/sideBar/ios/sideBar/sideBar/ViewModels/Chat/ChatViewModel+Realtime.swift"
        )

        let removedHandlerNames = [
            "func handleAssistantIdentityUpdated(",
            "func handleAssistantSoulUpdated(",
            "func handleNoteCreate(",
            "func handleNoteUpdate(",
            "func handleNoteDelete(",
            "func handleNotePinned(",
            "func handleNoteMoved(",
            "func handleWebsiteSaved(",
            "func handleWebsitePinned(",
            "func handleWebsiteArchived(",
            "func handleWebsiteDeleted(",
            "func handleIngestionUpdated(",
            "func handleThemeSet(",
            "func handleOtherPreferencesUpdated(",
            "func handleToolStart(",
            "func handleToolEnd(",
            "private enum DecodedRealtimeField",
            "private func decodeRealtimeField<"
        ]

        for handlerName in removedHandlerNames {
            XCTAssertFalse(
                source.contains(handlerName),
                "Expected dead chat sync helper to be removed: \(handlerName)"
            )
        }
    }

    func testChatViewModelArchitectureCommentPointsToStreamSyncDispatcher() throws {
        let source = try String(
            contentsOfFile: "/Users/sean/Coding/sideBar/ios/sideBar/sideBar/ViewModels/Chat/ChatViewModel.swift"
        )

        XCTAssertTrue(source.contains("`ChatStreamSyncDispatch.swift`: Primitive stream sync event handling"))
        XCTAssertFalse(source.contains("`ChatViewModel+Realtime.swift`: Real-time event processing"))
    }
}
