import Foundation

enum HeaderStatusKind: Equatable {
    case sync
    case ingestion
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
    let title: String
    let message: String?
    let rows: [HeaderStatusRowModel]
}

struct HeaderStatusRowModel: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String?
    let actions: [HeaderStatusActionModel]
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
