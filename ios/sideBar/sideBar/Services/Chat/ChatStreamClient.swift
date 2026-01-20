import Foundation

public protocol ChatStreamClient: AnyObject {
    var handler: ChatStreamEventHandler? { get set }
    func connect(request: ChatStreamRequest) async throws
    func disconnect()
}

public protocol ChatStreamEventHandler: AnyObject {
    func handle(event: ChatStreamEvent)
}

/// No-op chat stream client placeholder.
public final class PlaceholderChatStreamClient: ChatStreamClient {
    public weak var handler: ChatStreamEventHandler?

    public init(handler: ChatStreamEventHandler? = nil) {
        self.handler = handler
    }

    public func connect(request: ChatStreamRequest) async throws {
        _ = request
    }

    public func disconnect() {
    }
}
