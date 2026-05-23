import Foundation
import sideBarShared

@MainActor
extension WebsitesViewModel {
    public func requestYouTubeTranscript(websiteId: String, url: String) async {
        guard networkStatus.isOffline == false else {
            errorMessage = "Transcript requires an online connection."
            return
        }
        guard let videoId = YouTubeURLPolicy.extractVideoId(from: url) else {
            errorMessage = "Invalid YouTube URL."
            return
        }
        if isTranscriptPending(websiteId: websiteId, videoId: videoId) {
            return
        }
        setTranscriptRequestInFlight(true, websiteId: websiteId, videoId: videoId)
        defer {
            setTranscriptRequestInFlight(false, websiteId: websiteId, videoId: videoId)
        }

        do {
            let response = try await api.transcribeYouTube(id: websiteId, url: url)
            if let detail = response.readyWebsite {
                store.applyTranscriptReadyDetail(detail)
                stopTranscriptPolling(websiteId: websiteId, videoId: videoId)
                return
            }

            recordPendingTranscriptJob(websiteId: websiteId, videoId: videoId)
            if let transcriptJobId = response.queuedFileId {
                registerTranscriptJob(
                    websiteId: websiteId,
                    jobId: transcriptJobId
                )
            }
        } catch {
            errorMessage = ErrorMapping.message(for: error)
            showTranscriptFailureToast()
        }
    }

    public func isTranscriptPending(websiteId: String, videoId: String) -> Bool {
        let normalizedVideoId = videoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedVideoId.isEmpty else { return false }
        if let status = active?.youtubeTranscripts?[normalizedVideoId]?.status?.lowercased() {
            if Self.isTranscriptStatusPending(status) {
                return true
            }
            if status == "ready" || status == "failed" || status == "canceled" {
                return false
            }
        }
        if inFlightTranscriptRequests[websiteId]?.contains(normalizedVideoId) == true {
            return true
        }
        return pendingTranscriptJobs[websiteId]?.contains(normalizedVideoId) == true
    }

    public func applyRealtimeEvent(_ payload: RealtimePayload<WebsiteRealtimeRecord>) async {
        let websiteId = payload.record?.id ?? payload.oldRecord?.id
        if payload.eventType == .delete, selectedWebsiteId == websiteId {
            selectedWebsiteId = nil
        }
        store.applyRealtimeEvent(payload)
        if let record = payload.record,
           let item = RealtimeMappers.mapWebsite(record) {
            if payload.eventType == .insert {
                await applyWebsiteSaveRealtimeCompletion(from: item)
            }
            await applyTranscriptRealtimeProgress(from: item)
        }
    }

    func showTranscriptFailureToast() {
        toastCenter.show(message: "Couldn't get the transcript right now. Please try again.")
    }
}
