import Foundation

func ingestionStatusLabel(for job: IngestionJob) -> String? {
    let status = job.status?.lowercased() ?? ""
    guard !status.isEmpty else {
        return nil
    }
    let statusLabels: [String: String] = [
        "uploading": "Uploading...",
        "queued": "Queued",
        "ready": "Ready",
        "failed": "Failed",
        "canceled": "Canceled"
    ]
    if let label = statusLabels[status] {
        return label
    }

    let stage = job.stage?.lowercased() ?? ""
    let stageLabels: [String: String] = [
        "queued": "Queued",
        "validating": "Preparing",
        "converting": "Preparing",
        "extracting": "Preparing",
        "ai_md": "Transcribing",
        "transcribing": "Transcribing",
        "thumb": "Finalizing",
        "finalizing": "Finalizing",
        "ready": "Ready",
        "failed": "Failed",
        "canceled": "Canceled"
    ]
    return stageLabels[stage] ?? "Processing"
}
