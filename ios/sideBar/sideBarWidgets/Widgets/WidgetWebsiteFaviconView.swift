import SwiftUI

struct WidgetWebsiteFaviconView: View {
    let site: WidgetWebsite
    let size: CGFloat

    var body: some View {
        Group {
            if let faviconURL = site.resolvedFaviconURL {
                AsyncImage(url: faviconURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(2, size * 0.22), style: .continuous))
    }

    private var placeholder: some View {
        Image(systemName: "globe")
            .font(.system(size: max(6, size * 0.8)))
            .foregroundStyle(.secondary)
    }
}

extension WidgetWebsite {
    var resolvedFaviconURL: URL? {
        if let faviconR2Key,
           let r2URL = WidgetFaviconConfiguration.resolvedR2FaviconURL(for: faviconR2Key) {
            return r2URL
        }

        if let faviconUrl, let metadataURL = URL(string: faviconUrl),
           ["http", "https"].contains(metadataURL.scheme?.lowercased() ?? "") {
            return metadataURL
        }

        if let faviconUrl,
           let siteURL = URL(string: url),
           let relativeURL = URL(string: faviconUrl, relativeTo: siteURL)?.absoluteURL,
           ["http", "https"].contains(relativeURL.scheme?.lowercased() ?? "") {
            return relativeURL
        }

        guard let siteURL = URL(string: url),
              let scheme = siteURL.scheme,
              let host = siteURL.host,
              ["http", "https"].contains(scheme.lowercased()) else {
            return nil
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = "/favicon.ico"
        return components.url
    }

    var displayDomain: String {
        Self.extractBaseDomain(domain)
    }

    private static func extractBaseDomain(_ domain: String) -> String {
        let cleaned = domain.replacingOccurrences(
            of: "^www\\.",
            with: "",
            options: .regularExpression
        )
        let parts = cleaned.split(separator: ".").map(String.init)
        guard parts.count > 2 else { return cleaned }
        let secondLevelPrefixes: Set<String> = ["co", "com", "org", "net", "gov", "edu", "ac", "or"]
        let last = parts[parts.count - 1]
        let secondLast = parts[parts.count - 2]
        if secondLevelPrefixes.contains(secondLast.lowercased()) && last.count == 2 {
            return parts.suffix(3).joined(separator: ".")
        }
        return parts.suffix(2).joined(separator: ".")
    }
}

private enum WidgetFaviconConfiguration {
    private static let allowedSchemes: Set<String> = ["http", "https"]

    static func resolvedR2FaviconURL(for key: String) -> URL? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let publicBase = optionalHTTPURL(forInfoDictionaryKey: "R2_FAVICON_PUBLIC_BASE_URL") {
            return publicBase.appendingPathComponent(trimmed)
        }

        guard var endpoint = optionalHTTPURL(forInfoDictionaryKey: "R2_ENDPOINT") else {
            return nil
        }
        if let bucket = optionalString(forInfoDictionaryKey: "R2_FAVICON_BUCKET"), !bucket.isEmpty {
            endpoint = endpoint.appendingPathComponent(bucket)
        }
        return endpoint.appendingPathComponent(trimmed)
    }

    private static func optionalString(forInfoDictionaryKey key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else {
            return nil
        }
        return trimmed
    }

    private static func optionalHTTPURL(forInfoDictionaryKey key: String) -> URL? {
        guard let raw = optionalString(forInfoDictionaryKey: key),
              let parsed = URL(string: raw),
              let scheme = parsed.scheme?.lowercased(),
              allowedSchemes.contains(scheme) else {
            return nil
        }
        return parsed
    }
}
