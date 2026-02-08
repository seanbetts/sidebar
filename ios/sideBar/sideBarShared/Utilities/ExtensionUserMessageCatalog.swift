import Foundation

public enum ExtensionMessageCode: String {
    case savedForLater = "saved_for_later"
    case unsupportedAction = "unsupported_action"
    case missingURL = "missing_url"
    case invalidURL = "invalid_url"
    case noActiveURL = "no_active_url"
    case queueFailed = "queue_failed"
    case notAuthenticated = "not_authenticated"
    case invalidSharePayload = "invalid_share_payload"
    case unsupportedContent = "unsupported_content"
    case imageLoadFailed = "image_load_failed"
    case imageProcessFailed = "image_process_failed"
    case fileLoadFailed = "file_load_failed"
    case fileReadFailed = "file_read_failed"
    case uploadFailed = "upload_failed"
    case networkError = "network_error"
    case unknownFailure = "unknown_failure"
}

public enum ExtensionUserMessageCatalog {
    public static func message(for code: ExtensionMessageCode) -> String {
        switch code {
        case .savedForLater:
            return "Saved for later."
        case .unsupportedAction:
            return "This action is not supported."
        case .missingURL, .noActiveURL:
            return "No active tab URL found."
        case .invalidURL:
            return "That URL is invalid."
        case .queueFailed:
            return "Could not save for later."
        case .notAuthenticated:
            return "Please sign in to sideBar first."
        case .invalidSharePayload:
            return "Could not read the shared content."
        case .unsupportedContent:
            return "This content type is not supported."
        case .imageLoadFailed:
            return "Could not load the image."
        case .imageProcessFailed:
            return "Could not process the image."
        case .fileLoadFailed:
            return "Could not load the file."
        case .fileReadFailed:
            return "Could not read the file."
        case .uploadFailed:
            return "Upload failed. Please try again."
        case .networkError:
            return "Network error. Please try again."
        case .unknownFailure:
            return "Something went wrong. Please try again."
        }
    }

    public static func uploadFailureMessage(detail: String?) -> String {
        let base = message(for: .uploadFailed)
        guard let detail = sanitizedDetail(detail) else {
            return base
        }
        return "\(base) \(detail)"
    }

    public static func sanitizedDetail(_ detail: String?) -> String? {
        guard var detail else { return nil }
        detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !detail.isEmpty else { return nil }

        if detail.lowercased().hasPrefix("upload failed:") {
            detail = String(detail.dropFirst("upload failed:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if detail.lowercased().hasPrefix("the operation couldn") {
            return nil
        }

        guard !detail.isEmpty else { return nil }
        if detail.count > 120 {
            return String(detail.prefix(120)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return detail
    }
}
