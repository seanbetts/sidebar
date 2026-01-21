import Foundation

/// Represents ParsedSSEEvent.
public struct ParsedSSEEvent {
    public let type: String
    public let data: String
}

/// Parses server-sent events into chat stream events.
public struct ChatStreamParser {
    private var buffer = ""

    public init() {
    }

    public mutating func ingest(_ data: Data) -> [ChatStreamEvent] {
        guard let chunk = String(data: data, encoding: .utf8) else {
            return []
        }
        buffer.append(chunk)
        var output: [ChatStreamEvent] = []

        let events = buffer.components(separatedBy: "\n\n")
        buffer = events.last ?? ""

        for eventText in events.dropLast() {
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
        for line in text.split(separator: "\n") {
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
        guard let type = ChatStreamEventType(rawValue: event.type) else {
            return nil
        }
        let decoded = decodeAny(json: event.data)
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
