import Foundation
import sideBarShared

// MARK: - YouTubeURLPolicy

enum YouTubeURLPolicy {
    nonisolated static func normalizedCandidate(_ raw: String) -> String? {
        guard let trimmed = raw.trimmedOrNil else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate),
              let host = url.host?.lowercased(),
              isYouTubeHost(host),
              extractVideoId(from: candidate) != nil else {
            return nil
        }
        return url.absoluteString
    }

    nonisolated static func extractVideoId(from raw: String) -> String? {
        guard let trimmed = raw.trimmedOrNil else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: candidate),
              let host = components.host?.lowercased(),
              isYouTubeHost(host) else {
            return nil
        }

        let pathParts = components.path.split(separator: "/").map(String.init)
        if host == "youtu.be" || host.hasSuffix(".youtu.be") {
            guard let first = pathParts.first,
                  let videoId = first.trimmedOrNil,
                  isValidVideoId(videoId) else {
                return nil
            }
            return videoId
        }

        if let queryItems = components.queryItems,
           let videoId = queryItems.first(where: { $0.name == "v" })?.value?.trimmedOrNil,
           isValidVideoId(videoId) {
            return videoId
        }

        guard pathParts.count >= 2,
              let prefix = pathParts.first?.lowercased(),
              ["embed", "shorts", "live", "v"].contains(prefix),
              let videoId = pathParts[1].trimmedOrNil,
              isValidVideoId(videoId) else {
            return nil
        }
        return videoId
    }

    nonisolated static func embedURL(videoId: String) -> URL? {
        guard let trimmed = videoId.trimmedOrNil else { return nil }
        let query = "playsinline=1&rel=0&modestbranding=1&origin=https://www.youtube-nocookie.com"
        return URL(string: "https://www.youtube-nocookie.com/embed/\(trimmed)?\(query)")
    }

    nonisolated static func isYouTubeHost(_ rawHost: String) -> Bool {
        let host = rawHost.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return host == "youtube.com" ||
            host.hasSuffix(".youtube.com") ||
            host == "youtu.be" ||
            host.hasSuffix(".youtu.be")
    }

    nonisolated static func isValidVideoId(_ rawValue: String) -> Bool {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 6 else { return false }
        let pattern = "^[A-Za-z0-9_-]+$"
        return value.range(of: pattern, options: .regularExpression) != nil
    }
}
