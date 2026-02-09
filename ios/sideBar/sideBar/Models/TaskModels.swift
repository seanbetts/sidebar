import Foundation

/// Represents a task item struct.
public struct TaskItem: Codable, Identifiable, Equatable {
    /// The id value.
    public let id: String
    /// The title value.
    public let title: String
    /// The status value.
    public let status: String
    /// The deadline value.
    public let deadline: String?
    /// The notes value.
    public let notes: String?
    /// The project id value.
    public let projectId: String?
    /// The group id value.
    public let groupId: String?
    /// The repeating value.
    public let repeating: Bool?
    /// The repeat template value.
    public let repeatTemplate: Bool?
    /// The recurrence rule value.
    public let recurrenceRule: RecurrenceRule?
    /// The next instance date value.
    public let nextInstanceDate: String?
    /// The updated at value.
    public let updatedAt: String?
    /// The deleted at value.
    public let deletedAt: String?
    /// Indicates whether preview.
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

/// Represents a recurrence rule struct.
public struct RecurrenceRule: Codable, Equatable {
    /// The type value.
    public let type: String
    /// The interval value.
    public let interval: Int?
    /// The weekday value.
    public let weekday: Int?
    /// The day of month value.
    public let dayOfMonth: Int?

    private enum CodingKeys: String, CodingKey {
        case type
        case interval
        case weekday
        case dayOfMonth = "day_of_month"
    }
}

/// Represents a task group struct.
public struct TaskGroup: Codable, Identifiable, Equatable {
    /// The id value.
    public let id: String
    /// The title value.
    public let title: String
    /// The updated at value.
    public let updatedAt: String?
}

/// Represents a task project struct.
public struct TaskProject: Codable, Identifiable, Equatable {
    /// The id value.
    public let id: String
    /// The title value.
    public let title: String
    /// The group id value.
    public let groupId: String?
    /// The status value.
    public let status: String
    /// The updated at value.
    public let updatedAt: String?
}

/// Represents a task list response struct.
public struct TaskListResponse: Codable, Equatable {
    /// The scope value.
    public let scope: String
    /// The generated at value.
    public let generatedAt: String?
    /// The tasks value.
    public let tasks: [TaskItem]
    /// The projects value.
    public let projects: [TaskProject]?
    /// The groups value.
    public let groups: [TaskGroup]?
}

/// Represents a task counts response struct.
public struct TaskCountsResponse: Codable, Equatable {
    /// The generated at value.
    public let generatedAt: String?
    /// The counts value.
    public let counts: TaskCounts
    /// The projects value.
    public let projects: [TaskCountBucket]
    /// The groups value.
    public let groups: [TaskCountBucket]
}

/// Represents a task counts struct.
public struct TaskCounts: Codable, Equatable {
    /// The inbox value.
    public let inbox: Int
    /// The today value.
    public let today: Int
    /// The upcoming value.
    public let upcoming: Int
    /// The completed value.
    public let completed: Int
}

/// Represents a task count bucket struct.
public struct TaskCountBucket: Codable, Equatable {
    /// The id value.
    public let id: String
    /// The count value.
    public let count: Int
}

/// Represents a task sync response struct.
public struct TaskSyncResponse: Codable, Equatable {
    /// The applied value.
    public let applied: [String]
    /// The tasks value.
    public let tasks: [TaskItem]
    /// The next tasks value.
    public let nextTasks: [TaskItem]
    /// The conflicts value.
    public let conflicts: [TaskSyncConflict]
    /// The updates value.
    public let updates: TaskSyncUpdates?
    /// The server updated since value.
    public let serverUpdatedSince: String?
}

/// Represents a task sync updates struct.
public struct TaskSyncUpdates: Codable, Equatable {
    /// The tasks value.
    public let tasks: [TaskItem]
    /// The projects value.
    public let projects: [TaskProject]
    /// The groups value.
    public let groups: [TaskGroup]
}

/// Represents a task sync conflict struct.
public struct TaskSyncConflict: Codable, Equatable {
    /// The operation id value.
    public let operationId: String
    /// The op value.
    public let op: String?
    /// The id value.
    public let id: String
    /// The client updated at value.
    public let clientUpdatedAt: String?
    /// The server updated at value.
    public let serverUpdatedAt: String?
    /// The server task value.
    public let serverTask: TaskItem
}

/// Represents a task selection enum.
public enum TaskSelection: Equatable, Hashable {
    case none
    case inbox
    case today
    case upcoming
    case completed
    case group(id: String)
    case project(id: String)
    case search(query: String)

    /// The scope value.
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

    /// The cache key value.
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

/// Represents a task section struct.
public struct TaskSection: Identifiable, Equatable {
    /// The id value.
    public let id: String
    /// The title value.
    public let title: String
    /// The tasks value.
    public var tasks: [TaskItem]
}

/// Represents a task draft struct.
public struct TaskDraft: Equatable {
    /// The title value.
    public var title: String
    /// The notes value.
    public var notes: String
    /// The due date value.
    public var dueDate: Date?
    /// The list id value.
    public var listId: String?
    /// The list name value.
    public var listName: String?
    /// The selection value.
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
