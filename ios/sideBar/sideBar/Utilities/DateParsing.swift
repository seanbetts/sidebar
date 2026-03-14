import Foundation

public enum DateParsing {
    private static let fractionalSecondsFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let fallbackFormatter: ISO8601DateFormatter = {
        ISO8601DateFormatter()
    }()

    public static func parseISO8601(_ value: String?) -> Date? {
        guard let value else {
            return nil
        }
        if let date = fractionalSecondsFormatter.date(from: value) {
            return date
        }
        return fallbackFormatter.date(from: value)
    }

    static func parseISO8601TimeIntervalSince1970(_ value: String?) -> Double? {
        parseISO8601(value)?.timeIntervalSince1970
    }
}
