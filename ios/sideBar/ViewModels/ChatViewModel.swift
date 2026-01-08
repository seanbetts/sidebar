import Foundation
import Combine

@MainActor
public final class ChatViewModel: ObservableObject, ChatStreamEventHandler {
    @Published public private(set) var messages: [Message] = []
    @Published public private(set) var isStreaming: Bool = false
    @Published public private(set) var errorMessage: String? = nil

    private let conversationsAPI: ConversationsAPI
    private let chatAPI: ChatAPI
    private let streamClient: ChatStreamClient

    public init(conversationsAPI: ConversationsAPI, chatAPI: ChatAPI, streamClient: ChatStreamClient) {
        self.conversationsAPI = conversationsAPI
        self.chatAPI = chatAPI
        self.streamClient = streamClient
    }

    public func startStream(request: ChatStreamRequest) async {
        errorMessage = nil
        isStreaming = true
        do {
            try await streamClient.connect(request: request)
        } catch {
            errorMessage = error.localizedDescription
        }
        isStreaming = false
    }

    public func stopStream() {
        streamClient.disconnect()
        isStreaming = false
    }

    public func handle(event: ChatStreamEvent) {
        switch event.type {
        case .error:
            errorMessage = "Chat stream error"
        default:
            break
        }
    }
}
