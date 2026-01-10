import Foundation
import Combine

// TODO: Revisit to prefer native-first data sources where applicable.

@MainActor
public final class NotesViewModel: ObservableObject {
    @Published public private(set) var tree: FileTree? = nil
    @Published public private(set) var activeNote: NotePayload? = nil
    @Published public private(set) var selectedNoteId: String? = nil
    @Published public private(set) var errorMessage: String? = nil

    private let api: any NotesProviding
    private let cache: CacheClient
    private let scratchpadAPI: (any ScratchpadProviding)?
    private var scratchpadId: String?

    public init(
        api: any NotesProviding,
        cache: CacheClient,
        scratchpadAPI: (any ScratchpadProviding)? = nil
    ) {
        self.api = api
        self.cache = cache
        self.scratchpadAPI = scratchpadAPI
    }

    public func loadTree() async {
        errorMessage = nil
        let cached: FileTree? = cache.get(key: CacheKeys.notesTree)
        if let cached {
            tree = cached
        }
        do {
            let response = try await api.listTree()
            let enriched = await injectScratchpad(into: response)
            tree = enriched
            cache.set(key: CacheKeys.notesTree, value: enriched, ttlSeconds: CachePolicy.notesTree)
        } catch {
            if cached == nil {
                errorMessage = error.localizedDescription
            }
        }
    }

    public func loadNote(id: String) async {
        errorMessage = nil
        selectedNoteId = id
        let cacheKey = CacheKeys.note(id: id)
        let cached: NotePayload? = cache.get(key: cacheKey)
        if let cached {
            activeNote = cached
        }
        do {
            let response = try await api.getNote(id: id)
            activeNote = response
            cache.set(key: cacheKey, value: response, ttlSeconds: CachePolicy.noteContent)
        } catch {
            if cached == nil {
                errorMessage = error.localizedDescription
            }
        }
    }

    public func selectNote(id: String) async {
        await loadNote(id: id)
    }

    private func injectScratchpad(into tree: FileTree) async -> FileTree {
        guard let scratchpadAPI else {
            return tree
        }
        do {
            let scratchpad = try await scratchpadAPI.get()
            scratchpadId = scratchpad.id
            let node = FileNode(
                name: "\(scratchpad.title).md",
                path: scratchpad.id,
                type: .file,
                size: nil,
                modified: DateParsing.parseISO8601(scratchpad.updatedAt)?.timeIntervalSince1970,
                children: nil,
                expanded: nil,
                pinned: nil,
                pinnedOrder: nil,
                archived: nil,
                folderMarker: nil
            )
            if tree.children.contains(where: { $0.path == scratchpad.id }) {
                return tree
            }
            return FileTree(children: [node] + tree.children)
        } catch {
            return tree
        }
    }
}
