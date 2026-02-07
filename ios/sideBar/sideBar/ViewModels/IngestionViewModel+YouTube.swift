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
        YouTubeURLPolicy.embedURL(videoId: videoId)
    }

    func extractYouTubeVideoId(from raw: String) -> String? {
        YouTubeURLPolicy.extractVideoId(from: raw)
    }
}
