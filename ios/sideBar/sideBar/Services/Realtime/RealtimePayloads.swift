import Foundation

public enum RealtimeEventType: String, Codable {
    case insert = "INSERT"
    case update = "UPDATE"
    case delete = "DELETE"
}

public struct RealtimePayload<T: Codable>: Codable {
    public let eventType: RealtimeEventType
    public let table: String
    public let schema: String
    public let record: T?
    public let oldRecord: T?

    enum CodingKeys: String, CodingKey {
        case eventType = "eventType"
        case table
        case schema
        case record = "new"
        case oldRecord = "old"
    }
}

public enum RealtimeTable {
    public static let notes = "notes"
    public static let websites = "websites"
    public static let ingestedFiles = "ingested_files"
    public static let fileJobs = "file_processing_jobs"
}
