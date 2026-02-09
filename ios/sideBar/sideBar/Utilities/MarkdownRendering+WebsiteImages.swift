import Foundation

extension MarkdownRendering {
    nonisolated static func makeLinkedImageRegex() -> NSRegularExpression {
        let pattern = #"\[!\[([^\]]*)\]\(([^)\s]+)(?:\s+(?:\"([^\"]*)\"|'([^']*)'))?\)\]\(([^)\s]+)\)"#
        return makeRegex(pattern: pattern)
    }

    nonisolated static func makeBracketOnlyImageRegex() -> NSRegularExpression {
        let pattern = #"\[(!\[[^\]]*\]\([^\)\s]+(?:\s+(?:\"[^\"]*\"|'[^']*'))?\))\](?!\()"#
        return makeRegex(pattern: pattern)
    }

    nonisolated static func makeDanglingImageRegex() -> NSRegularExpression {
        let pattern = #"\[(!\[[^\]]*\]\([^\)\s]+(?:\s+(?:\"[^\"]*\"|'[^']*'))?\))(?!\])"#
        return makeRegex(pattern: pattern)
    }

    nonisolated static func normalizeLinkedImageWrappers(_ text: String) -> String {
        let regex = makeLinkedImageRegex()
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
        guard !matches.isEmpty else { return text }

        var output = text
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: output),
                  let altRange = Range(match.range(at: 1), in: output),
                  let imageRange = Range(match.range(at: 2), in: output),
                  let linkRange = Range(match.range(at: 5), in: output) else {
                continue
            }

            let alt = String(output[altRange])
            let imageURL = String(output[imageRange])
            let linkURL = String(output[linkRange])

            guard canonicalImageURL(imageURL) == canonicalImageURL(linkURL) else {
                continue
            }

            let title = titleForLinkedImageMatch(match, in: output)
            var replacement = "![\(alt)](\(imageURL)"
            if let title, !title.isEmpty {
                replacement += " \"\(title)\""
            }
            replacement += ")"
            output.replaceSubrange(fullRange, with: replacement)
        }
        return output
    }

    nonisolated static func normalizeBracketWrappedImages(_ text: String) -> String {
        let bracketOnlyRegex = makeBracketOnlyImageRegex()
        let danglingRegex = makeDanglingImageRegex()
        let bracketNormalized = unwrapImageGroupIfPresent(in: text, regex: bracketOnlyRegex)
        return unwrapImageGroupIfPresent(in: bracketNormalized, regex: danglingRegex)
    }

    nonisolated static func unwrapImageGroupIfPresent(
        in text: String,
        regex: NSRegularExpression
    ) -> String {
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
        guard !matches.isEmpty else { return text }

        var output = text
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: output),
                  let imageRange = Range(match.range(at: 1), in: output) else {
                continue
            }
            output.replaceSubrange(fullRange, with: output[imageRange])
        }
        return output
    }

    nonisolated static func titleForLinkedImageMatch(
        _ match: NSTextCheckingResult,
        in text: String
    ) -> String? {
        if let doubleQuoteTitleRange = Range(match.range(at: 3), in: text) {
            return String(text[doubleQuoteTitleRange])
        }
        if let singleQuoteTitleRange = Range(match.range(at: 4), in: text) {
            return String(text[singleQuoteTitleRange])
        }
        return nil
    }

    nonisolated static func canonicalImageURL(_ raw: String) -> String {
        guard !raw.isEmpty else { return raw }

        var unquoted = raw.removingPercentEncoding ?? raw
        if let embeddedRange = trailingHTTPRange(in: unquoted), embeddedRange.lowerBound > unquoted.startIndex {
            unquoted = String(unquoted[embeddedRange.lowerBound...])
        }

        if let components = URLComponents(string: unquoted),
           let scheme = components.scheme, !scheme.isEmpty,
           let host = components.host, !host.isEmpty {
            let normalizedHost = normalizedHostName(host)
            let path = components.path
            if normalizedHost.hasSuffix(".wp.com"),
               path.hasPrefix("/") {
                let parts = path.dropFirst().split(separator: "/", maxSplits: 1).map(String.init)
                if parts.count == 2, parts[0].contains(".") {
                    return "https://\(parts[0])/\(parts[1])"
                }
            }
            var normalized = components
            normalized.query = nil
            normalized.fragment = nil
            return normalized.string ?? unquoted
        }

        if let embeddedRange = trailingHTTPRange(in: unquoted) {
            return String(unquoted[embeddedRange.lowerBound...])
        }
        return unquoted
    }

    nonisolated static func trailingHTTPRange(in text: String) -> Range<String.Index>? {
        let httpRange = text.range(of: "http://", options: .backwards)
        let httpsRange = text.range(of: "https://", options: .backwards)
        switch (httpRange, httpsRange) {
        case let (lhs?, rhs?):
            return lhs.lowerBound > rhs.lowerBound ? lhs : rhs
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        case (nil, nil):
            return nil
        }
    }

    nonisolated static func normalizedHostName(_ host: String) -> String {
        var normalized = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if normalized.hasPrefix("www.") {
            normalized.removeFirst(4)
        }
        return normalized
    }
}
