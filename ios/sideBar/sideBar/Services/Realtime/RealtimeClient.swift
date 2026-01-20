import Foundation

public enum RealtimeChannelName: String {
    case notes
    case websites
    case ingestedFiles = "ingested_files"
    case fileJobs = "file_processing_jobs"
}

public protocol RealtimeClient {
    func start(userId: String, accessToken: String?) async
    func stop()
}

/// No-op realtime client placeholder.
public final class PlaceholderRealtimeClient: RealtimeClient {
    public init() {
    }

    public func start(userId: String, accessToken: String?) async {
        _ = userId
        _ = accessToken
    }

    public func stop() {
    }
}
