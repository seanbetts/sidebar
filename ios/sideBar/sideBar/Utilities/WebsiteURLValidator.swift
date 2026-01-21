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
        if host == "localhost" { return nil }
        if url.port != nil { return nil }
        if isIPv4Address(host) { return nil }
        if host.contains(":") { return nil }
        if !host.contains(".") { return nil }
        let labels = host.split(separator: ".")
        guard let tld = labels.last, tld.count >= 2, tld.count <= 24 else {
            return nil
        }
        if !isAlphaOnly(tld) { return nil }
        for label in labels {
            if label.isEmpty { return nil }
            if label.hasPrefix("-") || label.hasSuffix("-") { return nil }
            if !isAlphaNumericHyphen(label) { return nil }
        }
        return url
    }

    private static func isIPv4Address(_ host: String) -> Bool {
        let pattern = #"^\d{1,3}(\.\d{1,3}){3}$"#
        return host.range(of: pattern, options: .regularExpression) != nil
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
