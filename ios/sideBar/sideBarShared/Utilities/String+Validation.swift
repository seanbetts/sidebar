import Foundation

public extension StringProtocol {
    /// Returns the trimmed string, or nil if empty after trimming.
    nonisolated var trimmedOrNil: String? {
        let trimmed = self.trimmed
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Returns true if the string is empty or contains only whitespace.
    nonisolated var isBlank: Bool {
        trimmed.isEmpty
    }

    /// Returns the string trimmed of surrounding whitespace and newlines.
    nonisolated var trimmed: String {
        String(self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
