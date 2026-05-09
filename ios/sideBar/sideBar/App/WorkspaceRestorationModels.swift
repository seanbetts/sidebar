import Foundation

nonisolated extension AppSection: Codable {}
nonisolated extension WorkspacePane: Codable {}

nonisolated enum DeviceWorkspaceFamily: String, Codable, Equatable {
    case phone
    case workspace
}

nonisolated enum PhoneWorkspaceDetail: Codable, Equatable {
    case conversation(id: String)
    case chatDraft
    case note(id: String)
    case taskRoute(id: String)
    case website(id: String)
    case file(id: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case id
    }

    private enum DetailType: String, Codable {
        case conversation
        case chatDraft
        case note
        case taskRoute
        case website
        case file
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(DetailType.self, forKey: .type)
        switch type {
        case .conversation:
            self = .conversation(id: try container.decode(String.self, forKey: .id))
        case .chatDraft:
            self = .chatDraft
        case .note:
            self = .note(id: try container.decode(String.self, forKey: .id))
        case .taskRoute:
            self = .taskRoute(id: try container.decode(String.self, forKey: .id))
        case .website:
            self = .website(id: try container.decode(String.self, forKey: .id))
        case .file:
            self = .file(id: try container.decode(String.self, forKey: .id))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .conversation(let id):
            try container.encode(DetailType.conversation, forKey: .type)
            try container.encode(id, forKey: .id)
        case .chatDraft:
            try container.encode(DetailType.chatDraft, forKey: .type)
        case .note(let id):
            try container.encode(DetailType.note, forKey: .type)
            try container.encode(id, forKey: .id)
        case .taskRoute(let id):
            try container.encode(DetailType.taskRoute, forKey: .type)
            try container.encode(id, forKey: .id)
        case .website(let id):
            try container.encode(DetailType.website, forKey: .type)
            try container.encode(id, forKey: .id)
        case .file(let id):
            try container.encode(DetailType.file, forKey: .type)
            try container.encode(id, forKey: .id)
        }
    }
}

nonisolated struct PhoneWorkspaceRoute: Codable, Equatable {
    var section: AppSection
    var detail: PhoneWorkspaceDetail?
}

nonisolated enum WorkspaceDescriptorSnapshot: Codable, Equatable {
    case empty
    case builtIn(AppSection)

    private enum CodingKeys: String, CodingKey {
        case type
        case section
    }

    private enum DescriptorType: String, Codable {
        case empty
        case builtIn
    }

    init(descriptor: WorkspaceContentDescriptor) {
        switch descriptor {
        case .empty:
            self = .empty
        case .builtIn(let section):
            self = .builtIn(section)
        case .agentSurface:
            self = .empty
        }
    }

    var workspaceDescriptor: WorkspaceContentDescriptor {
        switch self {
        case .empty:
            return .empty
        case .builtIn(let section):
            return .builtIn(section)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(DescriptorType.self, forKey: .type)
        switch type {
        case .empty:
            self = .empty
        case .builtIn:
            self = .builtIn(try container.decode(AppSection.self, forKey: .section))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .empty:
            try container.encode(DescriptorType.empty, forKey: .type)
        case .builtIn(let section):
            try container.encode(DescriptorType.builtIn, forKey: .type)
            try container.encode(section, forKey: .section)
        }
    }
}

nonisolated struct SplitWorkspaceSnapshot: Codable, Equatable {
    var sidebarSelection: AppSection?
    var primaryDescriptor: WorkspaceDescriptorSnapshot
    var secondaryDescriptor: WorkspaceDescriptorSnapshot?
    var focusedPane: WorkspacePane
    var isLeftPanelExpanded: Bool
    var isWorkspaceExpanded: Bool
}

nonisolated struct DeviceWorkspaceSnapshot: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var userId: String?
    var family: DeviceWorkspaceFamily
    var updatedAt: Date
    var phoneRoute: PhoneWorkspaceRoute?
    var splitWorkspace: SplitWorkspaceSnapshot?

    var isCurrentSchema: Bool {
        schemaVersion == Self.currentSchemaVersion
    }
}
