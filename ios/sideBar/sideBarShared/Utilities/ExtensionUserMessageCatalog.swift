import Foundation

public enum ExtensionMessageCode: String, CaseIterable {
    case savedForLater = "saved_for_later"
    case savedForLaterSignInRequired = "saved_for_later_sign_in_required"
    case websiteSaved = "website_saved"
    case imageSaved = "image_saved"
    case fileSaved = "file_saved"
    case savingWebsite = "saving_website"
    case preparingImage = "preparing_image"
    case preparingFile = "preparing_file"
    case uploadingImage = "uploading_image"
    case uploadingFile = "uploading_file"
    case unsupportedAction = "unsupported_action"
    case missingURL = "missing_url"
    case invalidURL = "invalid_url"
    case noActiveURL = "no_active_url"
    case queueFailed = "queue_failed"
    case notAuthenticated = "not_authenticated"
    case invalidBaseUrl = "invalid_base_url"
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

/// Catalog of user-facing messages keyed by extension message code.
public enum ExtensionUserMessageCatalog {
    private static let messagesByCode: [ExtensionMessageCode: String] = [
        .savedForLater: "Saved for later.",
        .savedForLaterSignInRequired: "Saved for later. Open sideBar and sign in to finish saving.",
        .websiteSaved: "Website saved.",
        .imageSaved: "Image saved.",
        .fileSaved: "File saved.",
        .savingWebsite: "Saving website...",
        .preparingImage: "Preparing image...",
        .preparingFile: "Preparing file...",
        .uploadingImage: "Uploading image...",
        .uploadingFile: "Uploading file...",
        .unsupportedAction: "This action is not supported.",
        .missingURL: "No active tab URL found.",
        .invalidURL: "That URL is invalid.",
        .noActiveURL: "No active tab URL found.",
        .queueFailed: "Could not save for later.",
        .notAuthenticated: "Please sign in to sideBar first.",
        .invalidBaseUrl: "Invalid API base URL.",
        .invalidSharePayload: "Could not read the shared content.",
        .unsupportedContent: "This content type is not supported.",
        .imageLoadFailed: "Could not load the image.",
        .imageProcessFailed: "Could not process the image.",
        .fileLoadFailed: "Could not load the file.",
        .fileReadFailed: "Could not read the file.",
        .uploadFailed: "Upload failed. Please try again.",
        .networkError: "Network error. Please try again.",
        .unknownFailure: "Something went wrong. Please try again."
    ]

    public static func message(for code: ExtensionMessageCode) -> String {
        messagesByCode[code] ?? "Something went wrong. Please try again."
    }

    public static func uploadFailureMessage(detail: String?) -> String {
        let base = message(for: .uploadFailed)
        guard let detail = sanitizedDetail(detail) else {
            return base
        }
        return "\(base) \(detail)"
    }

    public static func sharedStorageUnavailableMessage() -> String {
        "Could not access shared storage. Open sideBar and try again."
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
