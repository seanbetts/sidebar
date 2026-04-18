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
        let notes = flattenNotes(from: response.children)

        return WidgetNoteData(
            notes: notes,
            totalCount: notes.count,
            lastUpdated: now
        )
    }

    private func flattenNotes(
        from nodes: [NotesWidgetNode],
        currentFolderPath: String = "/"
    ) -> [WidgetNote] {
        var notes: [WidgetNote] = []
        for node in nodes {
            if node.type == "file", node.archived != true {
                notes.append(
                    WidgetNote(
                        id: node.path,
                        name: node.name,
                        contentPreview: nil,
                        path: node.path,
                        scopePath: scopedNotePath(
                            noteIdentifier: node.path,
                            folderPath: currentFolderPath
                        ),
                        modifiedAt: node.modified.map { Date(timeIntervalSince1970: $0) },
                        pinned: node.pinned ?? false,
                        pinnedOrder: node.pinnedOrder
                    )
                )
            }
            if let children = node.children {
                let nextFolderPath = node.type == "directory"
                    ? folderPath(appending: node.name, to: currentFolderPath)
                    : currentFolderPath
                notes.append(
                    contentsOf: flattenNotes(
                        from: children,
                        currentFolderPath: nextFolderPath
                    )
                )
            }
        }
        return notes
    }

    private func folderPath(appending name: String, to currentFolderPath: String) -> String {
        let trimmedName = name.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmedName.isEmpty else { return currentFolderPath }
        if currentFolderPath == "/" {
            return "/\(trimmedName)"
        }
        return "\(currentFolderPath)/\(trimmedName)"
    }

    private func scopedNotePath(noteIdentifier: String, folderPath: String) -> String {
        let trimmedIdentifier = noteIdentifier.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmedIdentifier.isEmpty else { return folderPath }
        if folderPath == "/" {
            return "/\(trimmedIdentifier)"
        }
        return "\(folderPath)/\(trimmedIdentifier)"
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
