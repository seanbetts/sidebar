import Foundation

public struct WidgetTaskConfigurationProject: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let groupId: String?

    public init(id: String, title: String, groupId: String? = nil) {
        self.id = id
        self.title = title
        self.groupId = groupId
    }
}

public struct WidgetTaskConfigurationGroup: Codable, Equatable, Sendable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public struct WidgetTaskConfigurationCatalog: Codable, Equatable, Sendable {
    public let projects: [WidgetTaskConfigurationProject]
    public let groups: [WidgetTaskConfigurationGroup]

    public init(
        projects: [WidgetTaskConfigurationProject] = [],
        groups: [WidgetTaskConfigurationGroup] = []
    ) {
        self.projects = projects
        self.groups = groups
    }

    public static let empty = WidgetTaskConfigurationCatalog()
}

public struct WidgetNoteConfigurationFolder: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let path: String

    public init(id: String, title: String, path: String) {
        self.id = id
        self.title = title
        self.path = path
    }
}

public struct WidgetNoteConfigurationCatalog: Codable, Equatable, Sendable {
    public let folders: [WidgetNoteConfigurationFolder]

    public init(folders: [WidgetNoteConfigurationFolder] = []) {
        self.folders = folders
    }

    public static let empty = WidgetNoteConfigurationCatalog()
}
