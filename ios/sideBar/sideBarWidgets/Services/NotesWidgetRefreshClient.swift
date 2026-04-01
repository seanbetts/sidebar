import Foundation
import sideBarShared

struct NotesWidgetRefreshClient {
    private let apiClient: APIClient

    init(environment: WidgetAPIEnvironment) {
        self.apiClient = environment.apiClient
    }

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func refreshPinnedNotes(now: Date = Date()) async throws -> WidgetNoteData {
        let response: NotesWidgetTreeResponse = try await apiClient.request("notes/tree")
        let pinnedNotes = flattenNotes(from: response.children)
            .filter(\.pinned)
            .sorted { ($0.pinnedOrder ?? Int.max) < ($1.pinnedOrder ?? Int.max) }

        return WidgetNoteData(
            notes: Array(pinnedNotes.prefix(10)),
            totalCount: pinnedNotes.count,
            lastUpdated: now
        )
    }

    private func flattenNotes(from nodes: [NotesWidgetNode]) -> [WidgetNote] {
        var notes: [WidgetNote] = []
        for node in nodes {
            if node.type == "file", node.archived != true {
                notes.append(
                    WidgetNote(
                        id: node.path,
                        name: node.name,
                        contentPreview: nil,
                        path: node.path,
                        modifiedAt: node.modified.map { Date(timeIntervalSince1970: $0) },
                        pinned: node.pinned ?? false,
                        pinnedOrder: node.pinnedOrder
                    )
                )
            }
            if let children = node.children {
                notes.append(contentsOf: flattenNotes(from: children))
            }
        }
        return notes
    }
}

private struct NotesWidgetTreeResponse: Decodable {
    let children: [NotesWidgetNode]
}

private struct NotesWidgetNode: Decodable {
    let name: String
    let path: String
    let type: String
    let modified: Double?
    let children: [NotesWidgetNode]?
    let pinned: Bool?
    let pinnedOrder: Int?
    let archived: Bool?
}
