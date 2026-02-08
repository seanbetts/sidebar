import Foundation

enum ArchivedRetentionPolicy {
    static func contains(
        epochSeconds: Double?,
        retentionDays: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard let epochSeconds else {
            return false
        }
        return contains(
            date: Date(timeIntervalSince1970: epochSeconds),
            retentionDays: retentionDays,
            now: now,
            calendar: calendar
        )
    }

    static func contains(
        date: Date?,
        retentionDays: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard let date else {
            return false
        }
        guard let cutoff = calendar.date(byAdding: .day, value: -retentionDays, to: now) else {
            return false
        }
        return date >= cutoff
    }
}
