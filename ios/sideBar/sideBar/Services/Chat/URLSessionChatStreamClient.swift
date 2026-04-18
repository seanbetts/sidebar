import Foundation
import sideBarShared

/// Streams chat events over URLSession SSE.
public final class URLSessionChatStreamClient: ChatStreamClient {
    private struct StreamTaskState {
        let id: UUID
        let task: Task<Void, Error>
    }

    private let baseUrl: URL
    private let accessTokenProvider: () -> String?
    private let session: URLSession
    private var parser: ChatStreamParser
    public weak var handler: ChatStreamEventHandler?

    private let streamTaskLock = NSLock()
    private var streamTaskState: StreamTaskState?

    public init(
        baseUrl: URL,
        accessTokenProvider: @escaping () -> String?,
        session: URLSession = defaultSession(),
        parser: ChatStreamParser = ChatStreamParser(),
        handler: ChatStreamEventHandler? = nil
    ) {
        self.baseUrl = baseUrl
        self.accessTokenProvider = accessTokenProvider
        self.session = session
        self.parser = parser
        self.handler = handler
    }

    public static func defaultSession() -> URLSession {
        APIClient.makeDefaultSession()
    }

    public func connect(request: ChatStreamRequest) async throws {
        let intent = RequestIntent(
            operation: "chat.stream",
            path: "chat/stream",
            method: .post,
            requestKind: .sseStream,
            authRequirement: .required,
            replaySafety: .notReplaySafe,
            timeoutClass: .long
        )
        let client = APIClient(
            config: APIClientConfig(
                baseUrl: baseUrl,
                accessTokenProvider: accessTokenProvider
            ),
            session: session
        )
        var urlRequest = try client.buildRequest(
            intent.path,
            method: intent.method,
            headers: [
                "Accept": "text/event-stream",
                "Content-Type": "application/json"
            ]
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        urlRequest.httpBody = try encoder.encode(request)

        let streamTaskId = UUID()
        logConnectStart(request: request, streamTaskId: streamTaskId)
        let streamTask = Task {
            let (bytes, http) = try await client.executeStream(urlRequest, intent: intent)
            logConnectResponse(statusCode: http.statusCode, streamTaskId: streamTaskId)

            var buffer = Data()
            var previousByte: UInt8?
            for try await byte in bytes {
                if Task.isCancelled { break }
                buffer.append(byte)
                let reachedEventBoundary = previousByte == 0x0A && byte == 0x0A
                let reachedFlushSize = buffer.count >= 512
                if reachedEventBoundary || reachedFlushSize {
                    await emitEvents(
                        from: buffer,
                        streamTaskId: streamTaskId,
                        reason: reachedEventBoundary ? "boundary" : "size"
                    )
                    buffer.removeAll(keepingCapacity: true)
                }
                previousByte = byte
            }
            if !buffer.isEmpty {
                await emitEvents(from: buffer, streamTaskId: streamTaskId, reason: "eof")
            }
            logConnectEnd(streamTaskId: streamTaskId)
        }
        replaceStreamTask(with: StreamTaskState(id: streamTaskId, task: streamTask))?.task.cancel()
        defer {
            clearStreamTaskIfMatches(id: streamTaskId)
        }
        _ = try await streamTask.value
    }

    public func disconnect() {
        replaceStreamTask(with: nil)?.task.cancel()
    }

    private func emitEvents(from data: Data, streamTaskId: UUID, reason: String) async {
        let events = parser.ingest(data)
        logStreamFlush(
            streamTaskId: streamTaskId,
            reason: reason,
            byteCount: data.count,
            events: events
        )
        guard !events.isEmpty else { return }
        await MainActor.run { [handler = self.handler] in
            for event in events {
                handler?.handle(event: event)
            }
        }
    }

    private func replaceStreamTask(with state: StreamTaskState?) -> StreamTaskState? {
        streamTaskLock.lock()
        defer { streamTaskLock.unlock() }
        let previous = streamTaskState
        streamTaskState = state
        return previous
    }

    private func clearStreamTaskIfMatches(id: UUID) {
        streamTaskLock.lock()
        defer { streamTaskLock.unlock() }
        guard streamTaskState?.id == id else { return }
        streamTaskState = nil
    }

    private func logConnectStart(request: ChatStreamRequest, streamTaskId: UUID) {
        ChatStreamingDebugTrace.log(
            "connect.start",
            details: [
                "stream=\(ChatStreamingDebugTrace.shortID(streamTaskId.uuidString))",
                "conversation=\(ChatStreamingDebugTrace.shortID(request.conversationId))",
                "userMessage=\(ChatStreamingDebugTrace.shortID(request.userMessageId))",
                "assistantMessage=\(ChatStreamingDebugTrace.shortID(request.assistantMessageId))",
                "messageChars=\(request.message.count)",
                "attachments=\(request.attachments?.count ?? 0)"
            ].joined(separator: " ")
        )
    }

    private func logConnectResponse(statusCode: Int, streamTaskId: UUID) {
        ChatStreamingDebugTrace.log(
            "connect.response",
            details: [
                "stream=\(ChatStreamingDebugTrace.shortID(streamTaskId.uuidString))",
                "status=\(statusCode)"
            ].joined(separator: " ")
        )
    }

    private func logConnectEnd(streamTaskId: UUID) {
        ChatStreamingDebugTrace.log(
            "connect.end",
            details: "stream=\(ChatStreamingDebugTrace.shortID(streamTaskId.uuidString))"
        )
    }

    private func logStreamFlush(streamTaskId: UUID, reason: String, byteCount: Int, events: [ChatStreamEvent]) {
        ChatStreamingDebugTrace.log(
            "stream.flush",
            details: [
                "stream=\(ChatStreamingDebugTrace.shortID(streamTaskId.uuidString))",
                "reason=\(reason)",
                "bytes=\(byteCount)",
                "events=\(events.count)",
                "types=\(ChatStreamingDebugTrace.summarizeEventTypes(events))"
            ].joined(separator: " ")
        )
    }
}
