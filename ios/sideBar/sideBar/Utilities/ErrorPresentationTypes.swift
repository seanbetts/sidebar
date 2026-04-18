import sideBarShared

public struct ChatStreamErrorPresentation: Equatable {
    public let category: ChatStreamErrorCategory
    public let isRetryable: Bool
    public let title: String
    public let pillText: String
    public let userMessage: String
    public let details: String?
    public let requestID: String?
}

public enum ChatStreamErrorCategory: Equatable {
    case providerOverloaded
    case providerRateLimited
    case requestTimeout
    case transportFailure
    case emptyResponse
    case userCancelled
    case authOrPermission
    case contextTooLarge
    case toolExhaustion
    case unknown
}

public struct ErrorPresentationDecision: Equatable {
    public let surface: RecommendedSurface
    public let title: String
    public let message: String
    public let retryLabel: String?

    public init(
        surface: RecommendedSurface,
        title: String,
        message: String,
        retryLabel: String? = nil
    ) {
        self.surface = surface
        self.title = title
        self.message = message
        self.retryLabel = retryLabel
    }
}
