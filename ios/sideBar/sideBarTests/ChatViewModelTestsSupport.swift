import Foundation
import sideBarShared
@testable import sideBar

enum ChatViewModelTestsSupport {
    enum MockError: Error {
        case forced
    }

    struct TestNetworkStatus: NetworkStatusProviding {
        let isNetworkAvailable: Bool
        let isOffline: Bool

        init(isNetworkAvailable: Bool, isOffline: Bool = false) {
            self.isNetworkAvailable = isNetworkAvailable
            self.isOffline = isOffline
        }
    }

    @MainActor
    final class ConversationsAPISpy: ConversationsAPIProviding, ConversationsProviding {
        private(set) var getCallCount = 0

        func list() async throws -> [Conversation] {
            return []
        }

        func get(id: String) async throws -> ConversationWithMessages {
            _ = id
            getCallCount += 1
            throw MockError.forced
        }

        func search(query: String, limit: Int) async throws -> [Conversation] {
            _ = query
            _ = limit
            return []
        }

        func delete(conversationId: String) async throws -> Conversation {
            _ = conversationId
            throw MockError.forced
        }

        func create(title: String) async throws -> Conversation {
            _ = title
            throw MockError.forced
        }

        func addMessage(conversationId: String, message: ConversationMessageCreate) async throws -> Conversation {
            _ = conversationId
            _ = message
            throw MockError.forced
        }

        func update(conversationId: String, updates: ConversationUpdateRequest) async throws -> Conversation {
            _ = conversationId
            _ = updates
            throw MockError.forced
        }
    }

    final class MockChatStreamClient: ChatStreamClient {
        weak var handler: ChatStreamEventHandler?

        func connect(request: ChatStreamRequest) async throws {
            _ = request
        }

        func disconnect() {
        }
    }

    struct MockConversationsAPI: ConversationsAPIProviding, ConversationsProviding {
        let listResult: Result<[Conversation], Error>
        let getResult: Result<ConversationWithMessages, Error>
        let searchResult: Result<[Conversation], Error>
        let deleteResult: Result<Conversation, Error>
        let createResult: Result<Conversation, Error>
        let addMessageResult: Result<Conversation, Error>
        let updateResult: Result<Conversation, Error>

        init(
            listResult: Result<[Conversation], Error>,
            getResult: Result<ConversationWithMessages, Error> = .failure(MockError.forced),
            searchResult: Result<[Conversation], Error> = .success([]),
            deleteResult: Result<Conversation, Error> = .success(Conversation(
                id: "deleted",
                title: "Deleted",
                titleGenerated: false,
                createdAt: "",
                updatedAt: "",
                messageCount: 0,
                firstMessage: nil,
                isArchived: true
            )),
            createResult: Result<Conversation, Error> = .failure(MockError.forced),
            addMessageResult: Result<Conversation, Error> = .failure(MockError.forced),
            updateResult: Result<Conversation, Error> = .failure(MockError.forced)
        ) {
            self.listResult = listResult
            self.getResult = getResult
            self.searchResult = searchResult
            self.deleteResult = deleteResult
            self.createResult = createResult
            self.addMessageResult = addMessageResult
            self.updateResult = updateResult
        }

        func list() async throws -> [Conversation] {
            try listResult.get()
        }

        func get(id: String) async throws -> ConversationWithMessages {
            _ = id
            return try getResult.get()
        }

        func search(query: String, limit: Int) async throws -> [Conversation] {
            _ = query
            _ = limit
            return try searchResult.get()
        }

        func delete(conversationId: String) async throws -> Conversation {
            _ = conversationId
            return try deleteResult.get()
        }

        func create(title: String) async throws -> Conversation {
            _ = title
            return try createResult.get()
        }

        func addMessage(conversationId: String, message: ConversationMessageCreate) async throws -> Conversation {
            _ = conversationId
            _ = message
            return try addMessageResult.get()
        }

        func update(conversationId: String, updates: ConversationUpdateRequest) async throws -> Conversation {
            _ = conversationId
            _ = updates
            return try updateResult.get()
        }
    }
}
