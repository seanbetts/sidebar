import Foundation

func ingestionStatusLabel(for job: IngestionJob) -> String? {
    let status = job.status?.lowercased() ?? ""
    if status.isEmpty {
        return nil
    }
    switch status {
    case "uploading":
        return "Uploading..."
    case "queued":
        return "Queued"
    case "ready":
        return "Ready"
    case "failed":
        return "Failed"
    case "canceled":
        return "Canceled"
    default:
        break
    }

    let stage = job.stage?.lowercased() ?? ""
    switch stage {
    case "queued":
        return "Queued"
    case "validating", "converting", "extracting":
        return "Preparing"
    case "ai_md", "transcribing":
        return "Transcribing"
    case "thumb", "finalizing":
        return "Finalizing"
    case "ready":
        return "Ready"
    case "failed":
        return "Failed"
    case "canceled":
        return "Canceled"
    default:
        return "Processing"
    }
}
