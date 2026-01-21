import Foundation

/// Local UI state for chat attachments before they are sent with a message.
public struct ChatAttachmentItem: Identifiable, Equatable {
    public let id: String
    public let name: String
    public var status: ChatAttachmentStatus
    public var stage: String?
    public var fileId: String?
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
