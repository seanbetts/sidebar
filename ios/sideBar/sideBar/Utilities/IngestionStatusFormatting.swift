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

func ingestionStatusDetail(for job: IngestionJob, statusLabel: String?) -> String? {
    if let userMessage = normalizedIngestionStatusText(job.userMessage),
       !isDuplicateIngestionStatusText(userMessage, statusLabel: statusLabel) {
        return userMessage
    }
    if let errorMessage = normalizedIngestionStatusText(job.errorMessage),
       !isDuplicateIngestionStatusText(errorMessage, statusLabel: statusLabel) {
        return errorMessage
    }
    return nil
}

private func normalizedIngestionStatusText(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
        return nil
    }
    return trimmed
}

private func isDuplicateIngestionStatusText(_ message: String, statusLabel: String?) -> Bool {
    guard let label = normalizedIngestionStatusText(statusLabel) else {
        return false
    }
    return canonicalIngestionStatusText(message) == canonicalIngestionStatusText(label)
}

private func canonicalIngestionStatusText(_ value: String) -> String {
    value
        .lowercased()
        .replacingOccurrences(of: "_", with: " ")
        .replacingOccurrences(of: "...", with: "")
        .replacingOccurrences(of: "…", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
