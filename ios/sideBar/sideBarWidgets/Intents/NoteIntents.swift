import AppIntents
import WidgetKit
import os
import Foundation
import sideBarShared

// MARK: - Widget Configuration

enum NotesWidgetScope: String, AppEnum {
    case all
    case folder

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Notes Scope")
    static var caseDisplayRepresentations: [NotesWidgetScope: DisplayRepresentation] = [
        .all: DisplayRepresentation(title: "All pinned notes"),
        .folder: DisplayRepresentation(title: "Folder")
    ]
}

enum NotesWidgetSelection: Equatable, Sendable {
    case all
    case folder(path: String, title: String)

    var headerTitle: String {
        switch self {
        case .all:
            return "Notes"
        case .folder(_, let title):
            return title
        }
    }

    var deepLinkURL: URL {
        URL(string: "sidebar://notes")!
    }

    func filter(_ data: WidgetNoteData) -> WidgetNoteData {
        switch self {
        case .all:
            return data
        case .folder(let path, _):
            let normalizedPath = Self.normalizeFolderPath(path)
            let prefix = normalizedPath == "/" ? "/" : normalizedPath + "/"
            let filteredNotes = data.notes.filter { note in
                let notePath = Self.normalizeNotePath(note.path)
                return notePath.hasPrefix(prefix)
            }
            return WidgetNoteData(
                notes: filteredNotes,
                totalCount: filteredNotes.count,
                lastUpdated: data.lastUpdated
            )
        }
    }

    private static func normalizeFolderPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return "/" }
        return "/" + trimmed
    }

    private static func normalizeNotePath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return "/" }
        return "/" + trimmed
    }
}

struct NoteFolderEntity: AppEntity, Identifiable, Hashable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Note Folder")
    static var defaultQuery = NoteFolderEntityQuery()

    let id: String
    let title: String
    let path: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(path)")
    }
}

struct NoteFolderEntityQuery: EntityQuery {
    func entities(for identifiers: [NoteFolderEntity.ID]) async throws -> [NoteFolderEntity] {
        let folders = try await NotesWidgetConfigurationCatalogClient().folders()
        let foldersById = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        return identifiers.compactMap { id in
            foldersById[id] ?? NoteFolderEntity(
                id: id,
                title: NotesWidgetConfigurationCatalogClient.folderTitle(for: id),
                path: id
            )
        }
    }

    func suggestedEntities() async throws -> [NoteFolderEntity] {
        try await NotesWidgetConfigurationCatalogClient().folders()
    }
}

struct NotesWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Notes Widget"
    static var description = IntentDescription("Choose which notes the widget should show.")

    @Parameter(title: "Scope", default: .all)
    var scope: NotesWidgetScope

    @Parameter(title: "Folder")
    var folder: NoteFolderEntity?

    init() {
        scope = .all
    }

    init(selection: NotesWidgetSelection) {
        switch selection {
        case .all:
            scope = .all
        case .folder(let path, let title):
            scope = .folder
            folder = NoteFolderEntity(id: path, title: title, path: path)
        }
    }

    static var parameterSummary: some ParameterSummary {
        Switch(\.$scope) {
            Case(.folder) {
                Summary("Show notes from \(\.$folder)")
            }
            DefaultCase {
                Summary("Show \(\.$scope)")
            }
        }
    }

    var selection: NotesWidgetSelection {
        switch scope {
        case .all:
            return .all
        case .folder:
            if let folder {
                return .folder(path: folder.path, title: folder.title)
            }
            return .all
        }
    }
}

private struct NotesWidgetConfigurationCatalogClient {
    private let apiClient: APIClient

    init() throws {
        apiClient = try WidgetAPIEnvironment().apiClient
    }

    func folders() async throws -> [NoteFolderEntity] {
        let response: NotesWidgetTreeResponse = try await apiClient.request("notes/tree")
        return folderEntities(from: response.children)
    }

    private func folderEntities(from nodes: [NotesWidgetFolderNode]) -> [NoteFolderEntity] {
        var folders: [NoteFolderEntity] = []

        for node in nodes {
            guard node.type == "directory" else { continue }
            if node.name.lowercased() == "archive" { continue }

            let normalizedPath = Self.normalizeFolderPath(node.path)
            folders.append(
                NoteFolderEntity(
                    id: normalizedPath,
                    title: node.name,
                    path: normalizedPath
                )
            )

            if let children = node.children {
                folders.append(contentsOf: folderEntities(from: children))
            }
        }

        return folders.sorted { lhs, rhs in
            lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
        }
    }

    static func folderTitle(for path: String) -> String {
        let normalizedPath = normalizeFolderPath(path)
        return normalizedPath.split(separator: "/").last.map(String.init) ?? "Notes"
    }

    private static func normalizeFolderPath(_ path: String) -> String {
        let trimmed = path
            .replacingOccurrences(of: "folder:", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return "/" }
        return "/" + trimmed
    }
}

private struct NotesWidgetTreeResponse: Decodable {
    let children: [NotesWidgetFolderNode]
}

private struct NotesWidgetFolderNode: Decodable {
    let name: String
    let path: String
    let type: String
    let children: [NotesWidgetFolderNode]?
}

// MARK: - Open Note Intent

/// Intent to open a specific note in the app
struct OpenNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Note"
    static var description = IntentDescription("Opens a specific note in sideBar")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Note Path")
    var notePath: String

    init() {}

    init(notePath: String) {
        self.notePath = notePath
    }

    func perform() async throws -> some IntentResult & OpensIntent {
        let encodedPath = notePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? notePath
        guard let url = URL(string: "sidebar://notes/\(encodedPath)") else {
            return .result()
        }
        return .result(opensIntent: OpenURLIntent(url))
    }
}

// MARK: - Create Note Intent

/// Intent to open the app to create a new note
struct CreateNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Note"
    static var description = IntentDescription("Opens sideBar to create a new note")
    static var openAppWhenRun: Bool = true
    private let logger = Logger(subsystem: "sideBar", category: "WidgetIntent")

    func perform() async throws -> some IntentResult & OpensIntent {
        guard let url = URL(string: "sidebar://notes/new") else {
            logger.error("CreateNoteIntent failed: invalid deep link URL")
            return .result()
        }
        logger.info("CreateNoteIntent opening deep link")
        return .result(opensIntent: OpenURLIntent(url))
    }
}

// MARK: - Open Notes Intent

/// Intent to open the app to the notes view
struct OpenNotesIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Notes"
    static var description = IntentDescription("Opens sideBar to your notes")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & OpensIntent {
        guard let url = URL(string: "sidebar://notes") else {
            return .result()
        }
        return .result(opensIntent: OpenURLIntent(url))
    }
}

// Note: App shortcuts are combined in SideBarShortcutsProvider in TaskIntents.swift
// Only one AppShortcutsProvider is allowed per app
