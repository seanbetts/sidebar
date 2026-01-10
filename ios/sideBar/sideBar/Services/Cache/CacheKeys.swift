import Foundation

public enum CacheKeys {
    public static let conversationsList = "conversations.list"
    public static let notesTree = "notes.tree"
    public static let websitesList = "websites.list"
    public static let memoriesList = "memories.list"
    public static let ingestionList = "ingestion.list"
    public static let scratchpad = "scratchpad.content"
    public static let filesTreePrefix = "files.tree"
    public static let fileContentPrefix = "files.content"
    public static let userSettings = "settings.user"
    public static let skillsList = "settings.skills"
    public static let profileImage = "settings.profile-image"

    public static func note(id: String) -> String {
        "notes.note.\(id)"
    }

    public static func conversation(id: String) -> String {
        "conversations.detail.\(id)"
    }

    public static func websiteDetail(id: String) -> String {
        "websites.detail.\(id)"
    }

    public static func filesTree(basePath: String) -> String {
        "\(filesTreePrefix).\(basePath)"
    }

    public static func fileContent(basePath: String, path: String) -> String {
        "\(fileContentPrefix).\(basePath).\(path)"
    }
}
