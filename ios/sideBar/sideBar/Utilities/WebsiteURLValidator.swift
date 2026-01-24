import Foundation

enum WebsiteURLValidator {
    static func isValid(_ input: String) -> Bool {
        normalizedCandidate(input) != nil
    }

    static func normalizedCandidate(_ input: String) -> URL? {
        guard let trimmed = input.trimmedOrNil else { return nil }
        let candidate = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
            ? trimmed
            : "https://\(trimmed)"
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(),
              !host.isEmpty else {
            return nil
        }
        if url.port != nil { return nil }
        if !isValidHost(host) { return nil }
        return url
    }

    private static func isIPv4Address(_ host: String) -> Bool {
        let pattern = #"^\d{1,3}(\.\d{1,3}){3}$"#
        return host.range(of: pattern, options: .regularExpression) != nil
    }

    private static func isValidHost(_ host: String) -> Bool {
        if host == "localhost" { return false }
        if host.contains(":") { return false }
        if isIPv4Address(host) { return false }
        if !host.contains(".") { return false }

        let labels = host.split(separator: ".")
        guard let tld = labels.last, isValidTld(tld) else {
            return false
        }
        return labels.allSatisfy { isValidLabel($0) }
    }

    private static func isValidTld(_ value: Substring) -> Bool {
        let count = value.count
        return count >= 2 && count <= 24 && isAlphaOnly(value)
    }

    private static func isValidLabel(_ value: Substring) -> Bool {
        if value.isEmpty { return false }
        if value.hasPrefix("-") || value.hasSuffix("-") { return false }
        return isAlphaNumericHyphen(value)
    }

    private static func isAlphaOnly(_ value: Substring) -> Bool {
        for char in value {
            guard char.isLetter else { return false }
        }
        return true
    }

    private static func isAlphaNumericHyphen(_ value: Substring) -> Bool {
        for char in value {
            if char.isLetter || char.isNumber || char == "-" {
                continue
            }
            return false
        }
        return true
    }
}
