import Foundation

enum HeaderStatusKind: Equatable {
    case session
    case sync
    case ingestion
    case tool
}

enum HeaderStatusTone: Equatable {
    case progress
    case warning
    case error
    case success
}

struct HeaderStatusPillModel: Identifiable, Equatable {
    let id: String
    let kind: HeaderStatusKind
    let tone: HeaderStatusTone
    let label: String
    let accessibilityLabel: String
    let isActionable: Bool
    let expiresAfter: Duration?
    let popover: HeaderStatusPopoverModel
}

struct HeaderStatusPopoverModel: Equatable {
    let tone: HeaderStatusTone
    let title: String
    let message: String?
    let rows: [HeaderStatusRowModel]

    init(
        tone: HeaderStatusTone = .warning,
        title: String,
        message: String?,
        rows: [HeaderStatusRowModel]
    ) {
        self.tone = tone
        self.title = title
        self.message = message
        self.rows = rows
    }
}

struct HeaderStatusRowModel: Identifiable, Equatable {
    let tone: HeaderStatusTone
    let id: String
    let title: String
    let detail: String?
    let actions: [HeaderStatusActionModel]

    init(
        tone: HeaderStatusTone = .warning,
        id: String,
        title: String,
        detail: String?,
        actions: [HeaderStatusActionModel]
    ) {
        self.tone = tone
        self.id = id
        self.title = title
        self.detail = detail
        self.actions = actions
    }
}

struct HeaderStatusActionModel: Identifiable, Equatable {
    let id: String
    let title: String
    let role: HeaderStatusActionRole
}

enum HeaderStatusActionRole: Equatable {
    case `default`
    case cancel
    case destructive
}

enum HeaderSyncStatusSnapshot: Equatable {
    case syncing
    case pending
    case error(rows: [HeaderStatusRowModel])
}

enum HeaderIngestionStatusSnapshot: Equatable {
    case active(rows: [HeaderStatusRowModel])
    case success(messageID: String, title: String, message: String?)
    case failureWithoutAction(messageID: String, title: String, message: String?)
}

enum HeaderToolStatusSnapshot: Equatable {
    case active(name: String, status: ToolActivityStatus)
}

enum HeaderSessionStatusSnapshot: Equatable {
    case reconnecting
    case syncPaused
}
