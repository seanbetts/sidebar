import Foundation
import Combine
import CryptoKit

/// Defines CacheKeys.
public enum CacheKeys {
    public nonisolated static let conversationsList = "conversations.list"
    public nonisolated static let notesTree = "notes.tree"
    public nonisolated static let notesArchivedTree = "notes.archived.tree"
    public nonisolated static let notesArchivedSync = "notes.archived.sync"
    public nonisolated static let websitesList = "websites.list"
    public nonisolated static let websitesArchivedSync = "websites.archived.sync"
    public nonisolated static let memoriesList = "memories.list"
    public nonisolated static let ingestionList = "ingestion.list"
    public nonisolated static let ingestionMetaPrefix = "ingestion.meta"
    public nonisolated static let scratchpad = "scratchpad.content"
    public nonisolated static let filesTreePrefix = "files.tree"
    public nonisolated static let fileContentPrefix = "files.content"
    public nonisolated static let userSettings = "settings.user"
    public nonisolated static let skillsList = "settings.skills"
    public nonisolated static let profileImage = "settings.profile-image"
    public nonisolated static let tasksCounts = "tasks.counts"
    public nonisolated static let tasksSync = "tasks.sync"
    public nonisolated static let faviconPrefix = "favicon"

    public nonisolated static func note(id: String) -> String {
        "notes.note.\(id)"
    }

    public nonisolated static func conversation(id: String) -> String {
        "conversations.detail.\(id)"
    }

    public nonisolated static func conversationMessages(id: String) -> String {
        "conversations.messages.\(id)"
    }

    public nonisolated static func websiteDetail(id: String) -> String {
        "websites.detail.\(id)"
    }

    public nonisolated static func filesTree(basePath: String) -> String {
        "\(filesTreePrefix).\(basePath)"
    }

    public nonisolated static func fileContent(basePath: String, path: String) -> String {
        "\(fileContentPrefix).\(basePath).\(path)"
    }

    public nonisolated static func ingestionMeta(fileId: String) -> String {
        "\(ingestionMetaPrefix).\(fileId)"
    }

    public nonisolated static func tasksList(selectionKey: String) -> String {
        "tasks.list.\(selectionKey)"
    }

    public nonisolated static func favicon(url: String) -> String {
        "\(faviconPrefix).\(sha256Digest(url))"
    }

    private nonisolated static func sha256Digest(_ value: String) -> String {
        let data = Data(value.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
