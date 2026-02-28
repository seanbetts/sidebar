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

    static func normalizedPickerSelection(currentValue: String?, base: [String]) -> String {
        guard let currentValue else { return "" }
        let trimmedCurrentValue = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCurrentValue.isEmpty else { return "" }
        if let canonicalValue = base.first(where: {
            $0.caseInsensitiveCompare(trimmedCurrentValue) == .orderedSame
        }) {
            return canonicalValue
        }
        return trimmedCurrentValue
    }

    static func pickerValuesEquivalent(_ lhs: String, _ rhs: String?) -> Bool {
        normalizedComparablePickerValue(lhs) == normalizedComparablePickerValue(rhs)
    }

    private static func normalizedComparablePickerValue(_ value: String?) -> String {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }
}
