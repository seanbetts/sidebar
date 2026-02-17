import Foundation

extension ProfileSettingsView {
    static let genderOptions = [
        "female",
        "male",
        "non-binary",
        "agender",
        "genderfluid",
        "other",
        "prefer not to say"
    ]

    static let pronounOptions = [
        "he/him",
        "she/her",
        "they/them",
        "he/they",
        "she/they",
        "they/he",
        "they/she",
        "other"
    ]

    static func pickerOptions(base: [String], currentValue: String) -> [String] {
        let trimmedCurrentValue = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCurrentValue.isEmpty else {
            return base
        }
        let hasCurrentValue = base.contains {
            $0.caseInsensitiveCompare(trimmedCurrentValue) == .orderedSame
        }
        if hasCurrentValue {
            return base
        }
        return [trimmedCurrentValue] + base
    }
}
