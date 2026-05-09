import Foundation
import sideBarShared

enum ChatStreamSyncPayloadParser {
    static func parseEntityChanged(_ data: AnyCodable?) -> ChatEntityChangedPayload? {
        decode(ChatEntityChangedPayload.self, from: data)
    }

    static func parseEntityDeleted(_ data: AnyCodable?) -> ChatEntityDeletedPayload? {
        decode(ChatEntityDeletedPayload.self, from: data)
    }

    static func parseCollectionInvalidated(_ data: AnyCodable?) -> ChatCollectionInvalidatedPayload? {
        decode(ChatCollectionInvalidatedPayload.self, from: data)
    }

    static func parseToolStatus(_ data: AnyCodable?) -> ChatToolStatusPayload? {
        decode(ChatToolStatusPayload.self, from: data)
    }

    static func parseToolConfirmationRequested(_ data: AnyCodable?) -> ChatToolConfirmationRequestedPayload? {
        if let payload = dictionary(from: data) {
            return parseToolConfirmationRequested(payload)
        }
        return decode(ChatToolConfirmationRequestedPayload.self, from: data)
    }

    static func parseToolConfirmationResolved(_ data: AnyCodable?) -> ChatToolConfirmationResolvedPayload? {
        decode(ChatToolConfirmationResolvedPayload.self, from: data)
    }

    static func parseUndoAvailable(_ data: AnyCodable?) -> ChatUndoAvailablePayload? {
        decode(ChatUndoAvailablePayload.self, from: data)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: AnyCodable?) -> T? {
        guard let data else {
            return nil
        }
        guard let encoded = try? JSONEncoder().encode(data) else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: encoded)
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
