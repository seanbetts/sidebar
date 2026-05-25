import Foundation

/// Decides whether widgets may render protected cached content.
public enum WidgetDisplayAuthorization {
    /// Returns whether a widget may display content for the current auth and cache state.
    public static func canDisplayContent(
        isAuthenticated: Bool,
        hasCachedSnapshot: Bool
    ) -> Bool {
        isAuthenticated || hasCachedSnapshot
    }
}
