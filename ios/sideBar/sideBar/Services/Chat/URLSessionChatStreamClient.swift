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
        session: URLSession = .shared,
        parser: ChatStreamParser = ChatStreamParser(),
        handler: ChatStreamEventHandler? = nil
    ) {
        self.baseUrl = baseUrl
        self.accessTokenProvider = accessTokenProvider
        self.session = session
        self.parser = parser
        self.handler = handler
    }

    public func connect(request: ChatStreamRequest) async throws {
        let url = baseUrl.appendingPathComponent("chat/stream")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = accessTokenProvider() {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        urlRequest.httpBody = try encoder.encode(request)

        let streamTaskId = UUID()
        let streamTask = Task {
            let (bytes, response) = try await session.bytes(for: urlRequest)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw APIClientError.requestFailed((response as? HTTPURLResponse)?.statusCode ?? 0)
            }

            var buffer = Data()
            for try await byte in bytes {
                if Task.isCancelled { break }
                buffer.append(byte)
                if buffer.count >= 1024 {
                    emitEvents(from: buffer)
                    buffer.removeAll(keepingCapacity: true)
                }
            }
            if !buffer.isEmpty {
                emitEvents(from: buffer)
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

    private func emitEvents(from data: Data) {
        let events = parser.ingest(data)
        guard !events.isEmpty else { return }
        Task { @MainActor [handler = self.handler] in
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
}
