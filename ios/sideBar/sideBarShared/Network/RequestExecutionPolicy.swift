import Foundation

public enum HTTPMethod: Equatable, Sendable {
    case get
    case post
    case put
    case patch
    case delete
    case head
    case options
    case custom(String)

    public init(_ rawValue: String) {
        switch rawValue.uppercased() {
        case "GET":
            self = .get
        case "POST":
            self = .post
        case "PUT":
            self = .put
        case "PATCH":
            self = .patch
        case "DELETE":
            self = .delete
        case "HEAD":
            self = .head
        case "OPTIONS":
            self = .options
        default:
            self = .custom(rawValue.uppercased())
        }
    }

    public var rawValue: String {
        switch self {
        case .get:
            return "GET"
        case .post:
            return "POST"
        case .put:
            return "PUT"
        case .patch:
            return "PATCH"
        case .delete:
            return "DELETE"
        case .head:
            return "HEAD"
        case .options:
            return "OPTIONS"
        case .custom(let value):
            return value
        }
    }
}

public enum AuthRequirement: Equatable, Sendable {
    case required
    case optional
    case none
}

public enum TimeoutClass: Equatable, Sendable {
    case standard
    case long
}

public enum RequestKind: String, Equatable, Sendable {
    case foregroundRead
    case foregroundMutation
    case sseStream
    case multipartUpload
    case backgroundUpload
    case widgetRefresh
    case healthProbe
    case offlineReplay
}

public enum ReplaySafety: Equatable, Sendable {
    case safeToReplayBeforeBodyStarts
    case safeToReplayAlways
    case notReplaySafe
}

public enum Retryability: String, Equatable, Sendable {
    case notRetryable
    case retryable
    case userActionRequired
    case allowsOfflineHandoff

    public var allowsOfflineHandoff: Bool {
        self == .allowsOfflineHandoff
    }
}

public enum RecommendedSurface: String, Equatable, Sendable {
    case toast
    case alert
    case inline
    case placeholder
    case chatError
    case offlineBanner
    case silent
}

public struct RequestIntent: Equatable, Sendable {
    public let operation: String
    public let path: String
    public let method: HTTPMethod
    public let requestKind: RequestKind
    public let authRequirement: AuthRequirement
    public let replaySafety: ReplaySafety
    public let timeoutClass: TimeoutClass

    public init(
        operation: String,
        path: String,
        method: HTTPMethod,
        requestKind: RequestKind,
        authRequirement: AuthRequirement,
        replaySafety: ReplaySafety,
        timeoutClass: TimeoutClass
    ) {
        self.operation = operation
        self.path = path
        self.method = method
        self.requestKind = requestKind
        self.authRequirement = authRequirement
        self.replaySafety = replaySafety
        self.timeoutClass = timeoutClass
    }
}

public enum RequestLifecycleStage: String, Equatable, Sendable {
    case started
    case succeeded
    case failed
    case cancelled
    case retried
    case offlineHandedOff
}

public struct RequestLifecycleSignal: Equatable, Sendable {
    public let operation: String
    public let requestKind: RequestKind
    public let stage: RequestLifecycleStage
    public let errorCategory: AppError.Category?
    public let metadata: [String: String]

    public init(
        operation: String,
        requestKind: RequestKind,
        stage: RequestLifecycleStage,
        errorCategory: AppError.Category? = nil,
        metadata: [String: String] = [:]
    ) {
        self.operation = operation
        self.requestKind = requestKind
        self.stage = stage
        self.errorCategory = errorCategory
        self.metadata = metadata
    }
}

public enum RequestExecutionPolicy {
    public static func shouldAttemptAuthRefresh(for intent: RequestIntent) -> Bool {
        guard intent.authRequirement == .required else {
            return false
        }

        switch intent.replaySafety {
        case .safeToReplayBeforeBodyStarts, .safeToReplayAlways:
            return true
        case .notReplaySafe:
            return false
        }
    }
}
