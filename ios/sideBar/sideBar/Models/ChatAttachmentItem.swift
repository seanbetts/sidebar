import Foundation

/// Local UI state for chat attachments before they are sent with a message.
public struct ChatAttachmentItem: Identifiable, Equatable {
    /// The id value.
    public let id: String
    /// The name value.
    public let name: String
    /// The status value.
    public var status: ChatAttachmentStatus
    /// The stage value.
    public var stage: String?
    /// The file id value.
    public var fileId: String?
    /// The file url value.
    public var fileURL: URL?

    public init(
        id: String,
        name: String,
        status: ChatAttachmentStatus,
        stage: String? = nil,
        fileId: String? = nil,
        fileURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.stage = stage
        self.fileId = fileId
        self.fileURL = fileURL
    }
}

extension ChatAttachmentItem: StatusFilterable {
    /// The status value value.
    public var statusValue: String {
        status.rawValue
    }
}

/// Upload lifecycle for a chat attachment.
public enum ChatAttachmentStatus: String, Equatable {
    case uploading
    case queued
    case ready
    case failed
    case canceled
}
