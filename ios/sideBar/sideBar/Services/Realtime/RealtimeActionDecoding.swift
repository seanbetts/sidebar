import Foundation
import Realtime

protocol RealtimeActionDecoding {
    func decodeRecord<T: Decodable>(decoder: JSONDecoder) throws -> T
    func decodeOldRecord<T: Decodable>(decoder: JSONDecoder) throws -> T
}

enum RealtimeActionDecodingError: Error {
    case missingRecord
    case missingOldRecord
}

struct SupabaseInsertActionAdapter: RealtimeActionDecoding {
    let action: InsertAction

    func decodeRecord<T: Decodable>(decoder: JSONDecoder) throws -> T {
        try action.decodeRecord(decoder: decoder)
    }

    func decodeOldRecord<T: Decodable>(decoder: JSONDecoder) throws -> T {
        _ = decoder
        throw RealtimeActionDecodingError.missingOldRecord
    }
}

struct SupabaseUpdateActionAdapter: RealtimeActionDecoding {
    let action: UpdateAction

    func decodeRecord<T: Decodable>(decoder: JSONDecoder) throws -> T {
        try action.decodeRecord(decoder: decoder)
    }

    func decodeOldRecord<T: Decodable>(decoder: JSONDecoder) throws -> T {
        try action.decodeOldRecord(decoder: decoder)
    }
}

struct SupabaseDeleteActionAdapter: RealtimeActionDecoding {
    let action: DeleteAction

    func decodeRecord<T: Decodable>(decoder: JSONDecoder) throws -> T {
        _ = decoder
        throw RealtimeActionDecodingError.missingRecord
    }

    func decodeOldRecord<T: Decodable>(decoder: JSONDecoder) throws -> T {
        try action.decodeOldRecord(decoder: decoder)
    }
}
