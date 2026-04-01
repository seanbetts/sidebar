import Foundation

public enum WidgetRefreshPolicy {
    public static func staleThreshold(for contentType: WidgetContentType) -> TimeInterval {
        switch contentType {
        case .tasks:
            return 5 * 60
        case .notes, .websites, .files:
            return 15 * 60
        }
    }

    public static func shouldRefresh(
        lastUpdated: Date?,
        contentType: WidgetContentType,
        now: Date = Date()
    ) -> Bool {
        guard let lastUpdated else {
            return true
        }
        return now.timeIntervalSince(lastUpdated) > staleThreshold(for: contentType)
    }
}
