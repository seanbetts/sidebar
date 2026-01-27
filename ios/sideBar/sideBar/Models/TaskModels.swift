import Foundation

public struct TaskItem: Codable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let status: String
    public let deadline: String?
    public let notes: String?
    public let projectId: String?
    public let groupId: String?
    public let repeating: Bool?
    public let repeatTemplate: Bool?
    public let recurrenceRule: RecurrenceRule?
    public let nextInstanceDate: String?
    public let updatedAt: String?
    public let deletedAt: String?
    public var isPreview: Bool = false

    public init(
        id: String,
        title: String,
        status: String,
        deadline: String? = nil,
        notes: String? = nil,
        projectId: String? = nil,
        groupId: String? = nil,
        repeating: Bool? = nil,
        repeatTemplate: Bool? = nil,
        recurrenceRule: RecurrenceRule? = nil,
        nextInstanceDate: String? = nil,
        updatedAt: String? = nil,
        deletedAt: String? = nil,
        isPreview: Bool = false
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.deadline = deadline
        self.notes = notes
        self.projectId = projectId
        self.groupId = groupId
        self.repeating = repeating
        self.repeatTemplate = repeatTemplate
        self.recurrenceRule = recurrenceRule
        self.nextInstanceDate = nextInstanceDate
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.isPreview = isPreview
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case status
        case deadline
        case notes
        case projectId
        case groupId
        case repeating
        case repeatTemplate
        case recurrenceRule
        case nextInstanceDate
        case updatedAt
        case deletedAt
    }
}

public struct RecurrenceRule: Codable, Equatable {
    public let type: String
    public let interval: Int?
    public let weekday: Int?
    public let dayOfMonth: Int?

    private enum CodingKeys: String, CodingKey {
        case type
        case interval
        case weekday
        case dayOfMonth = "day_of_month"
    }
}

public struct TaskGroup: Codable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let updatedAt: String?
}

public struct TaskProject: Codable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let groupId: String?
    public let status: String
    public let updatedAt: String?
}

public struct TaskListResponse: Codable, Equatable {
    public let scope: String
    public let generatedAt: String?
    public let tasks: [TaskItem]
    public let projects: [TaskProject]?
    public let groups: [TaskGroup]?
}

public struct TaskCountsResponse: Codable, Equatable {
    public let generatedAt: String?
    public let counts: TaskCounts
    public let projects: [TaskCountBucket]
    public let groups: [TaskCountBucket]
}

public struct TaskCounts: Codable, Equatable {
    public let inbox: Int
    public let today: Int
    public let upcoming: Int
    public let completed: Int
}

public struct TaskCountBucket: Codable, Equatable {
    public let id: String
    public let count: Int
}

public struct TaskSyncResponse: Codable, Equatable {
    public let applied: [String]
    public let tasks: [TaskItem]
    public let nextTasks: [TaskItem]
    public let conflicts: [TaskSyncConflict]
    public let updates: TaskSyncUpdates?
    public let serverUpdatedSince: String?
}

public struct TaskSyncUpdates: Codable, Equatable {
    public let tasks: [TaskItem]
    public let projects: [TaskProject]
    public let groups: [TaskGroup]
}

public struct TaskSyncConflict: Codable, Equatable {
    public let operationId: String
    public let op: String?
    public let id: String
    public let clientUpdatedAt: String?
    public let serverUpdatedAt: String?
    public let serverTask: TaskItem
}

public enum TaskSelection: Equatable, Hashable {
    case none
    case inbox
    case today
    case upcoming
    case completed
    case group(id: String)
    case project(id: String)
    case search(query: String)

    public var scope: String? {
        switch self {
        case .none:
            return nil
        case .inbox:
            return "inbox"
        case .today:
            return "today"
        case .upcoming:
            return "upcoming"
        case .completed:
            return "completed"
        case .group:
            return "group"
        case .project:
            return "project"
        case .search:
            return nil
        }
    }

    public var cacheKey: String {
        switch self {
        case .none:
            return "none"
        case .inbox:
            return "inbox"
        case .today:
            return "today"
        case .upcoming:
            return "upcoming"
        case .completed:
            return "completed"
        case .group(let id):
            return "group:\(id)"
        case .project(let id):
            return "project:\(id)"
        case .search(let query):
            return "search:\(query)"
        }
    }
}

public struct TaskSection: Identifiable, Equatable {
    public let id: String
    public let title: String
    public var tasks: [TaskItem]
}

public struct TaskDraft: Equatable {
    public var title: String
    public var notes: String
    public var dueDate: Date?
    public var listId: String?
    public var listName: String?
    public var selection: TaskSelection

    public init(
        title: String = "",
        notes: String = "",
        dueDate: Date? = nil,
        listId: String? = nil,
        listName: String? = nil,
        selection: TaskSelection = .today
    ) {
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.listId = listId
        self.listName = listName
        self.selection = selection
    }
}
