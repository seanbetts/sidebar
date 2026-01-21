import Foundation

/// Describes a file notification ready to be displayed.
public struct ReadyFileNotification: Identifiable, Equatable {
    public let id: String
    public let fileId: String
    public let filename: String

    public init(fileId: String, filename: String) {
        self.id = fileId
        self.fileId = fileId
        self.filename = filename
    }
}
