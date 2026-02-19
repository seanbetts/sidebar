import Foundation

enum SearchTextMatcher {
    static func normalizedQuery(_ value: String) -> String {
        normalize(value).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func contains(normalizedQuery: String, in candidates: [String]) -> Bool {
        guard !normalizedQuery.isEmpty else {
            return true
        }
        return candidates.contains { candidate in
            normalize(candidate).contains(normalizedQuery)
        }
    }

    private static func normalize(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
    }
}
