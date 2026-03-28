import Foundation
import OSLog
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
    private let logger = Logger(subsystem: "sideBar", category: "ChatStreamClient")

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
        let url = baseUrl.appendingPathComponent("chat/stream")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let appVersion = AppVersionHeader.currentValue() {
            urlRequest.setValue(appVersion, forHTTPHeaderField: AppVersionHeader.fieldName)
        }
        if let token = accessTokenProvider() {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        urlRequest.httpBody = try encoder.encode(request)

        let streamTaskId = UUID()
        let streamTask = Task {
            let (bytes, response) = try await session.bytes(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                throw APIClientError.unknown
            }
            guard (200...299).contains(http.statusCode) else {
                let errorData = try await collectBytes(from: bytes)
                if let message = decodeAPIErrorMessage(from: errorData) {
                    logger.error(
                        "Chat stream request failed status=\(http.statusCode) message=\(message, privacy: .public)"
                    )
                    throw APIClientError.apiError(message)
                }
                if let bodyPreview = String(data: errorData.prefix(2000), encoding: .utf8),
                   !bodyPreview.isEmpty {
                    logger.error(
                        "Chat stream request failed status=\(http.statusCode) body=\(bodyPreview, privacy: .private)"
                    )
                } else {
                    logger.error("Chat stream request failed status=\(http.statusCode)")
                }
                throw APIClientError.requestFailed(http.statusCode)
            }

            var buffer = Data()
            var previousByte: UInt8?
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

    private func collectBytes(from bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }
        return data
    }

    private func decodeAPIErrorMessage(from data: Data) -> String? {
        guard !data.isEmpty else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return APIClient.decodeErrorMessage(data: data, decoder: decoder)
    }
}
