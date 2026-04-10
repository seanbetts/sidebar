import Foundation

#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

public struct IngestionProgressActivityAttributes: Hashable {
    public struct ContentState: Codable, Hashable {
        public let status: String
        public let stage: String
        public let progress: Double?
        public let statusText: String
        public let detailText: String?

        public init(
            status: String,
            stage: String,
            progress: Double?,
            statusText: String,
            detailText: String?
        ) {
            self.status = status
            self.stage = stage
            self.progress = progress
            self.statusText = statusText
            self.detailText = detailText
        }
    }

    public let fileID: String
    public let displayName: String

    public init(fileID: String, displayName: String) {
        self.fileID = fileID
        self.displayName = displayName
    }
}

#if canImport(ActivityKit) && os(iOS)
extension IngestionProgressActivityAttributes: ActivityAttributes {}
#endif
