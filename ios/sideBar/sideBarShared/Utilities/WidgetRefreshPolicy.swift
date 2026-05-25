import Foundation

/// Defines widget snapshot staleness thresholds and retry timing.
public enum WidgetRefreshPolicy {
    /// Returns the stale threshold for a widget content type.
    public static func staleThreshold(for contentType: WidgetContentType) -> TimeInterval {
        switch contentType {
        case .tasks:
            return 5 * 60
        case .notes, .websites, .files:
            return 15 * 60
        }
    }

    /// Returns whether a stored snapshot should be refreshed.
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

    /// Returns the next date a widget should request another refresh.
    public static func nextRefreshDate(
        lastUpdated: Date?,
        contentType: WidgetContentType,
        now: Date = Date()
    ) -> Date {
        let threshold = staleThreshold(for: contentType)
        guard let lastUpdated else {
            return now.addingTimeInterval(threshold)
        }

        let boundary = lastUpdated.addingTimeInterval(threshold)
        if boundary > now {
            return boundary
        }

        // If the snapshot is already stale and a refresh attempt fails,
        // back off by one threshold instead of requesting an immediate retry loop.
        return now.addingTimeInterval(threshold)
    }
}
