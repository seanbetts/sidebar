import sideBarShared

public nonisolated struct ChatStreamErrorPresentation: Equatable {
    public let category: ChatStreamErrorCategory
    public let isRetryable: Bool
    public let title: String
    public let pillText: String
    public let userMessage: String
    public let details: String?
    public let requestID: String?
    public let assistantContext: String?
    public let assistantExplanation: String?

    public init(
        category: ChatStreamErrorCategory,
        isRetryable: Bool,
        title: String,
        pillText: String,
        userMessage: String,
        details: String?,
        requestID: String?,
        assistantContext: String? = nil,
        assistantExplanation: String? = nil
    ) {
        self.category = category
        self.isRetryable = isRetryable
        self.title = title
        self.pillText = pillText
        self.userMessage = userMessage
        self.details = details
        self.requestID = requestID
        self.assistantContext = assistantContext
        self.assistantExplanation = assistantExplanation
    }
}

public nonisolated enum ChatStreamErrorCategory: Equatable {
    case providerBilling
    case providerOverloaded
    case providerRateLimited
    case providerError
    case requestTimeout
    case transportFailure
    case emptyResponse
    case userCancelled
    case authOrPermission
    case contextTooLarge
    case toolExhaustion
    case unknown
}

public nonisolated struct ErrorPresentationDecision: Equatable {
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
