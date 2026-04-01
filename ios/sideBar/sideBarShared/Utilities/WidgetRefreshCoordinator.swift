import Foundation

public struct WidgetRefreshDecision: Equatable {
    public let shouldAttemptRefresh: Bool
    public let shouldRenderCachedContent: Bool

    public init(shouldAttemptRefresh: Bool, shouldRenderCachedContent: Bool) {
        self.shouldAttemptRefresh = shouldAttemptRefresh
        self.shouldRenderCachedContent = shouldRenderCachedContent
    }
}

public enum WidgetRefreshCoordinator {
    public static func decision(
        contentType: WidgetContentType,
        lastUpdated: Date?,
        hasCachedSnapshot: Bool,
        isAuthenticated: Bool,
        now: Date = Date()
    ) -> WidgetRefreshDecision {
        let shouldRenderCachedContent = hasCachedSnapshot
        let shouldAttemptRefresh =
            isAuthenticated &&
            WidgetRefreshPolicy.shouldRefresh(
                lastUpdated: lastUpdated,
                contentType: contentType,
                now: now
            )

        return WidgetRefreshDecision(
            shouldAttemptRefresh: shouldAttemptRefresh,
            shouldRenderCachedContent: shouldRenderCachedContent
        )
    }
}
