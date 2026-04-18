import Foundation

/// Lightweight note model for widgets.
public struct WidgetNote: WidgetStorable {
    public let id: String
    public let name: String
    public let contentPreview: String?
    public let path: String
    public let scopePath: String?
    public let modifiedAt: Date?
    public let pinned: Bool
    public let pinnedOrder: Int?

    public init(
        id: String,
        name: String,
        contentPreview: String? = nil,
        path: String,
        scopePath: String? = nil,
        modifiedAt: Date? = nil,
        pinned: Bool = false,
        pinnedOrder: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.contentPreview = contentPreview
        self.path = path
        self.scopePath = scopePath
        self.modifiedAt = modifiedAt
        self.pinned = pinned
        self.pinnedOrder = pinnedOrder
    }
}

/// Data snapshot for note widgets.
public struct WidgetNoteData: WidgetDataContainer {
    public typealias Item = WidgetNote

    public let notes: [WidgetNote]
    public let totalCount: Int
    public let lastUpdated: Date

    public var items: [WidgetNote] { notes }

    public init(notes: [WidgetNote], totalCount: Int, lastUpdated: Date = Date()) {
        self.notes = notes
        self.totalCount = totalCount
        self.lastUpdated = lastUpdated
    }

    public static let empty = WidgetNoteData(notes: [], totalCount: 0)

    public static let placeholder = WidgetNoteData(
        notes: [
            WidgetNote(
                id: "1",
                name: "Meeting Notes",
                contentPreview: "Discussed project timeline...",
                path: "/notes/meeting",
                scopePath: "/notes/meeting",
                pinned: true,
                pinnedOrder: 0
            ),
            WidgetNote(
                id: "2",
                name: "Ideas",
                contentPreview: "New feature concepts",
                path: "/notes/ideas",
                scopePath: "/notes/ideas",
                pinned: true,
                pinnedOrder: 1
            )
        ],
        totalCount: 2
    )
}
