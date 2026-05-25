import Foundation

/// Describes whether a widget should refresh and whether cached content can be rendered.
public struct WidgetRefreshDecision: Equatable {
    /// Whether the widget should attempt to fetch a fresh snapshot.
    public let shouldAttemptRefresh: Bool
    /// Whether the widget should render cached content while offline or signed out.
    public let shouldRenderCachedContent: Bool

    /// Creates a widget refresh decision.
    public init(shouldAttemptRefresh: Bool, shouldRenderCachedContent: Bool) {
        self.shouldAttemptRefresh = shouldAttemptRefresh
        self.shouldRenderCachedContent = shouldRenderCachedContent
    }
}

/// Combines auth, cache, and staleness state into widget refresh decisions.
public enum WidgetRefreshCoordinator {
    /// Returns the refresh decision for a widget content type.
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
