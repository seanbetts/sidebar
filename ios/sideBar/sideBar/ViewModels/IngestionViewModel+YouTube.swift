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
        guard let normalized = normalizeYouTubeUrlCandidate(raw),
              let url = URL(string: normalized) else {
            return nil
        }
        let host = url.host?.lowercased() ?? ""
        if host.contains("youtu.be") {
            return url.pathComponents.last?.trimmedOrNil
        }
        guard host.contains("youtube.com") else {
            return nil
        }
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems,
           let videoId = queryItems.first(where: { $0.name == "v" })?.value?.trimmedOrNil {
            return videoId
        }
        let components = url.pathComponents.filter { $0 != "/" }
        if let embedIndex = components.firstIndex(of: "embed"),
           components.indices.contains(embedIndex + 1) {
            return components[embedIndex + 1].trimmedOrNil
        }
        if let shortsIndex = components.firstIndex(of: "shorts"),
           components.indices.contains(shortsIndex + 1) {
            return components[shortsIndex + 1].trimmedOrNil
        }
        if let liveIndex = components.firstIndex(of: "live"),
           components.indices.contains(liveIndex + 1) {
            return components[liveIndex + 1].trimmedOrNil
        }
        return components.last?.trimmedOrNil
    }
}
