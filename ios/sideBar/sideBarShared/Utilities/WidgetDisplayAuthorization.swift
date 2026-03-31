import Foundation

public enum WidgetDisplayAuthorization {
    public static func canDisplayContent(
        isAuthenticated: Bool,
        hasCachedSnapshot: Bool
    ) -> Bool {
        isAuthenticated || hasCachedSnapshot
    }
}
