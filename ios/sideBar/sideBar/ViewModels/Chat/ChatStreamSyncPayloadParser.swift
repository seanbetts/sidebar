import Foundation
import sideBarShared

enum ChatStreamSyncPayloadParseFailure: Equatable {
    case missingPayload
    case encodingFailed(keys: [String])
    case malformedPayload(keys: [String])

    var reason: String {
        switch self {
        case .missingPayload:
            "missing"
        case .encodingFailed:
            "encoding_failed"
        case .malformedPayload:
            "malformed"
        }
    }

    var payloadKeys: [String] {
        switch self {
        case .missingPayload:
            []
        case .encodingFailed(let keys),
             .malformedPayload(let keys):
            keys
        }
    }
}

enum ChatStreamSyncPayloadParseResult<Payload> {
    case success(Payload)
    case failure(ChatStreamSyncPayloadParseFailure)

    var payload: Payload? {
        guard case .success(let payload) = self else { return nil }
        return payload
    }
}

enum ChatStreamSyncPayloadParser {
    static func parseEntityChanged(_ data: AnyCodable?) -> ChatEntityChangedPayload? {
        parseEntityChangedResult(data).payload
    }

    static func parseEntityChangedResult(
        _ data: AnyCodable?
    ) -> ChatStreamSyncPayloadParseResult<ChatEntityChangedPayload> {
        decode(ChatEntityChangedPayload.self, from: data)
    }

    static func parseEntityDeleted(_ data: AnyCodable?) -> ChatEntityDeletedPayload? {
        parseEntityDeletedResult(data).payload
    }

    static func parseEntityDeletedResult(
        _ data: AnyCodable?
    ) -> ChatStreamSyncPayloadParseResult<ChatEntityDeletedPayload> {
        decode(ChatEntityDeletedPayload.self, from: data)
    }

    static func parseCollectionInvalidated(_ data: AnyCodable?) -> ChatCollectionInvalidatedPayload? {
        parseCollectionInvalidatedResult(data).payload
    }

    static func parseCollectionInvalidatedResult(
        _ data: AnyCodable?
    ) -> ChatStreamSyncPayloadParseResult<ChatCollectionInvalidatedPayload> {
        decode(ChatCollectionInvalidatedPayload.self, from: data)
    }

    static func parseToolStatus(_ data: AnyCodable?) -> ChatToolStatusPayload? {
        parseToolStatusResult(data).payload
    }

    static func parseToolStatusResult(
        _ data: AnyCodable?
    ) -> ChatStreamSyncPayloadParseResult<ChatToolStatusPayload> {
        decode(ChatToolStatusPayload.self, from: data)
    }

    static func parseToolConfirmationRequested(_ data: AnyCodable?) -> ChatToolConfirmationRequestedPayload? {
        parseToolConfirmationRequestedResult(data).payload
    }

    static func parseToolConfirmationRequestedResult(
        _ data: AnyCodable?
    ) -> ChatStreamSyncPayloadParseResult<ChatToolConfirmationRequestedPayload> {
        if let payload = dictionary(from: data) {
            if let parsed = parseToolConfirmationRequested(payload) {
                return .success(parsed)
            }
            return .failure(.malformedPayload(keys: payload.keys.sorted()))
        }
        return decode(ChatToolConfirmationRequestedPayload.self, from: data)
    }

    static func parseToolConfirmationResolved(_ data: AnyCodable?) -> ChatToolConfirmationResolvedPayload? {
        parseToolConfirmationResolvedResult(data).payload
    }

    static func parseToolConfirmationResolvedResult(
        _ data: AnyCodable?
    ) -> ChatStreamSyncPayloadParseResult<ChatToolConfirmationResolvedPayload> {
        decode(ChatToolConfirmationResolvedPayload.self, from: data)
    }

    static func parseUndoAvailable(_ data: AnyCodable?) -> ChatUndoAvailablePayload? {
        parseUndoAvailableResult(data).payload
    }

    static func parseUndoAvailableResult(
        _ data: AnyCodable?
    ) -> ChatStreamSyncPayloadParseResult<ChatUndoAvailablePayload> {
        decode(ChatUndoAvailablePayload.self, from: data)
    }

    private static func decode<T: Decodable>(
        _ type: T.Type,
        from data: AnyCodable?
    ) -> ChatStreamSyncPayloadParseResult<T> {
        guard let data else {
            return .failure(.missingPayload)
        }
        let keys = payloadKeys(from: data)
        guard let encoded = try? JSONEncoder().encode(data) else {
            return .failure(.encodingFailed(keys: keys))
        }
        do {
            return .success(try JSONDecoder().decode(T.self, from: encoded))
        } catch {
            return .failure(.malformedPayload(keys: keys))
        }
    }

    private static func parseToolConfirmationRequested(
        _ payload: [String: Any]
    ) -> ChatToolConfirmationRequestedPayload? {
        guard let confirmationId = stringValue(payload["confirmation_id"] ?? payload["confirmationId"]),
              let toolName = stringValue(payload["tool_name"] ?? payload["toolName"]),
              let summary = stringValue(payload["summary"]) else {
            return nil
        }
        return ChatToolConfirmationRequestedPayload(
            confirmationId: confirmationId,
            toolCallId: stringValue(payload["tool_call_id"] ?? payload["toolCallId"]),
            toolName: toolName,
            summary: summary,
            guardReason: stringValue(payload["guard_reason"] ?? payload["guardReason"]),
            undoSupported: boolValue(payload["undo_supported"] ?? payload["undoSupported"]) ?? false,
            expiresAt: stringValue(payload["expires_at"] ?? payload["expiresAt"])
        )
    }

    private static func dictionary(from data: AnyCodable?) -> [String: Any]? {
        data?.value as? [String: Any]
    }

    private static func payloadKeys(from data: AnyCodable) -> [String] {
        dictionary(from: data)?.keys.sorted() ?? []
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let anyCodable as AnyCodable:
            return stringValue(anyCodable.value)
        default:
            return nil
        }
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        switch value {
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            return number.boolValue
        case let string as String:
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1":
                return true
            case "false", "0":
                return false
            default:
                return nil
            }
        case let anyCodable as AnyCodable:
            return boolValue(anyCodable.value)
        default:
            return nil
        }
    }
}
