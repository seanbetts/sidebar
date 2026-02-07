import Foundation
import sideBarShared

extension IngestionViewModel {
    func buildYouTubeEmbedURL(from file: IngestedFileMeta) -> URL? {
        if let metadata = file.sourceMetadata {
            if let value = metadata["video_id"]?.value as? String {
                return makeYouTubeEmbedURL(videoId: value)
            }
            if let value = metadata["youtube_url"]?.value as? String,
               let videoId = extractYouTubeVideoId(from: value) {
                return makeYouTubeEmbedURL(videoId: videoId)
            }
        }
        if let raw = file.sourceUrl,
           let videoId = extractYouTubeVideoId(from: raw) {
            return makeYouTubeEmbedURL(videoId: videoId)
        }
        return nil
    }

    func makeYouTubeEmbedURL(videoId: String) -> URL? {
        guard let trimmed = videoId.trimmedOrNil else { return nil }
        let base = "https://www.youtube-nocookie.com/embed/\(trimmed)"
        let query = "playsinline=1&rel=0&modestbranding=1&origin=https://www.youtube-nocookie.com"
        let url = "\(base)?\(query)"
        return URL(string: url)
    }

    func extractYouTubeVideoId(from raw: String) -> String? {
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
                  let candidateId = first.trimmedOrNil,
                  isValidYouTubeVideoId(candidateId) else {
                return nil
            }
            return candidateId
        }

        if let queryItems = components.queryItems,
           let videoId = queryItems.first(where: { $0.name == "v" })?.value?.trimmedOrNil,
           isValidYouTubeVideoId(videoId) {
            return videoId
        }

        guard pathParts.count >= 2 else {
            return nil
        }
        guard let kind = pathParts.first?.lowercased(),
              ["embed", "shorts", "live", "v"].contains(kind) else {
            return nil
        }
        guard let candidateId = pathParts[1].trimmedOrNil,
              isValidYouTubeVideoId(candidateId) else {
            return nil
        }
        return candidateId
    }
}
