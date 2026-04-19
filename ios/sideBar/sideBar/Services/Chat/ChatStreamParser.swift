import Foundation
import sideBarShared

/// Represents ParsedSSEEvent.
public struct ParsedSSEEvent {
    public let type: String
    public let data: String
}

/// Parses server-sent events into chat stream events.
public struct ChatStreamParser {
    private var buffer = Data()
    private let maxBufferSize: Int
    private static let eventDelimiter = Data("\n\n".utf8)

    public init(maxBufferSize: Int = 65_536) {
        self.maxBufferSize = maxBufferSize
    }

    public mutating func ingest(_ data: Data) -> [ChatStreamEvent] {
        guard !data.isEmpty else {
            return []
        }
        buffer.append(data)
        if buffer.count > maxBufferSize {
            buffer = Data(buffer.suffix(maxBufferSize))
        }
        var output: [ChatStreamEvent] = []

        while let range = buffer.range(of: Self.eventDelimiter) {
            let eventData = Data(buffer[..<range.lowerBound])
            buffer.removeSubrange(..<range.upperBound)
            guard let eventText = String(data: eventData, encoding: .utf8) else {
                continue
            }
            let parsed = parseEvent(eventText)
            for sseEvent in parsed {
                if let mapped = mapEvent(sseEvent) {
                    output.append(mapped)
                }
            }
        }
        return output
    }

    private func parseEvent(_ text: String) -> [ParsedSSEEvent] {
        var eventType = "message"
        var dataLines: [String] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("event:") {
                eventType = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                let value = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                dataLines.append(String(value))
            }
        }
        guard !dataLines.isEmpty else {
            return []
        }
        let data = dataLines.joined(separator: "\n")
        return [ParsedSSEEvent(type: eventType, data: data)]
    }

    private func mapEvent(_ event: ParsedSSEEvent) -> ChatStreamEvent? {
        guard let type = chatStreamEventTypeByName[event.type] else {
            ChatStreamingDebugTrace.log(
                "parser.ignoredUnknownEvent",
                details: "type=\(event.type)"
            )
            return nil
        }
        let decoded = decodeAny(json: event.data)
        if type == .token,
           let payload = decoded?.value as? [String: Any],
           let content = (payload["content"] as? String) ?? (payload["text"] as? String) {
            ChatStreamingDebugTrace.log(
                "parser.token",
                details: [
                    "chars=\(content.count)",
                    "content=\"\(ChatStreamingDebugTrace.visibleWhitespacePreview(content))\""
                ].joined(separator: " ")
            )
        }
        return ChatStreamEvent(type: type, data: decoded)
    }

    private func decodeAny(json: String) -> AnyCodable? {
        guard let data = json.data(using: .utf8) else {
            return nil
        }
        if let object = try? JSONSerialization.jsonObject(with: data) {
            return AnyCodable(object)
        }
        return nil
    }
}
