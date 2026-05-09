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
        let streamTask = Task {
            let (bytes, _) = try await client.executeStream(urlRequest, intent: intent)

            var buffer = Data()
            var previousByte: UInt8?
            do {
                for try await byte in bytes {
                    if Task.isCancelled { break }
                    buffer.append(byte)
                    let reachedEventBoundary = previousByte == 0x0A && byte == 0x0A
                    let reachedFlushSize = buffer.count >= 512
                    if reachedEventBoundary || reachedFlushSize {
                        await emitEvents(from: buffer)
                        buffer.removeAll(keepingCapacity: true)
                    }
                    previousByte = byte
                }
            } catch {
                client.postFailureNotification(intent: intent, transportError: error)
                throw error
            }
            if !buffer.isEmpty {
                await emitEvents(from: buffer)
            }
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

    private func emitEvents(from data: Data) async {
        let events = parser.ingest(data)
        guard !events.isEmpty else { return }
        traceEvents(events)
        await MainActor.run { [handler = self.handler] in
            for event in events {
                handler?.handle(event: event)
            }
        }
    }

    private func traceEvents(_ events: [ChatStreamEvent]) {
        let tracedEvents = events.filter { event in
            switch event.type {
            case .toolCall,
                 .toolConfirmationRequested,
                 .toolConfirmationResolved,
                 .toolStatus,
                 .toolResult,
                 .complete,
                 .error:
                return true
            default:
                return false
            }
        }
        guard !tracedEvents.isEmpty else { return }
        for event in tracedEvents {
            ChatStreamDebugTrace.log(
                "client.event",
                details: [
                    "type=\(event.type.rawValue)",
                    "keys=\(ChatStreamDebugTrace.payloadKeys(event.data))"
                ]
            )
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
}
