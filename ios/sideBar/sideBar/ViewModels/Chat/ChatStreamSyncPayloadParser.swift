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

    private static func decode<T: Decodable>(_ type: T.Type, from data: AnyCodable?) -> T? {
        guard let data else {
            return nil
        }
        guard let encoded = try? JSONEncoder().encode(data) else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: encoded)
    }
}
