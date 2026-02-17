import XCTest
@testable import sideBar

@MainActor
final class NotesPanelTreeHelpersTests: XCTestCase {
    func testMainNodesSortUnpinnedNotesByMostRecentModified() async {
        let tree = FileTree(children: [
            makeFile(path: "note-old", name: "Old.md", modified: 100),
            makeFile(path: "note-pinned", name: "Pinned.md", modified: 400, pinned: true, pinnedOrder: 0),
            makeFile(path: "note-new", name: "New.md", modified: 300),
            makeFile(path: "note-mid", name: "Mid.md", modified: 200)
        ])
        let viewModel = makeViewModel(tree: tree)

        await viewModel.loadTree()
        let panel = NotesPanelView(viewModel: viewModel)

        XCTAssertEqual(panel.mainNodes.map(\.path), ["note-new", "note-mid", "note-old"])
    }

    func testPinnedItemsUsePinnedOrderNotRecency() async {
        let tree = FileTree(children: [
            makeFile(path: "pin-first", name: "First.md", modified: 100, pinned: true, pinnedOrder: 0),
            makeFile(path: "pin-second", name: "Second.md", modified: 500, pinned: true, pinnedOrder: 2)
        ])
        let viewModel = makeViewModel(tree: tree)

        await viewModel.loadTree()
        let panel = NotesPanelView(viewModel: viewModel)

        XCTAssertEqual(panel.pinnedItems.map(\.id), ["pin-first", "pin-second"])
    }

    func testMainNodesSortFolderChildrenByMostRecent() async {
        let folder = FileNode(
            name: "Work",
            path: "folder:Work",
            type: .directory,
            size: nil,
            modified: nil,
            created: nil,
            children: [
                makeFile(path: "work-old", name: "WorkOld.md", modified: 100),
                makeFile(path: "work-new", name: "WorkNew.md", modified: 200)
            ],
            expanded: nil,
            pinned: nil,
            pinnedOrder: nil,
            archived: nil,
            folderMarker: nil
        )
        let tree = FileTree(children: [folder])
        let viewModel = makeViewModel(tree: tree)

        await viewModel.loadTree()
        let panel = NotesPanelView(viewModel: viewModel)

        let children = panel.mainNodes.first?.children ?? []
        XCTAssertEqual(children.map(\.path), ["work-new", "work-old"])
    }
}

@MainActor
private func makeViewModel(tree: FileTree) -> NotesViewModel {
    let api = StaticTreeNotesAPI(tree: tree)
    let store = NotesStore(api: api, cache: InMemoryCacheClient())
    return NotesViewModel(
        api: api,
        store: store,
        toastCenter: ToastCenter(),
        networkStatus: PanelTestNetworkStatus(isNetworkAvailable: true)
    )
}

private func makeFile(
    path: String,
    name: String,
    modified: Double?,
    pinned: Bool = false,
    pinnedOrder: Int? = nil
) -> FileNode {
    FileNode(
        name: name,
        path: path,
        type: .file,
        size: nil,
        modified: modified,
        created: nil,
        children: nil,
        expanded: nil,
        pinned: pinned,
        pinnedOrder: pinnedOrder,
        archived: false,
        folderMarker: nil
    )
}

@MainActor
private struct PanelTestNetworkStatus: NetworkStatusProviding {
    let isNetworkAvailable: Bool
    let isOffline: Bool = false
}

private enum StaticTreeAPIError: Error {
    case unused
}

private final class StaticTreeNotesAPI: NotesProviding {
    private let tree: FileTree

    init(tree: FileTree) {
        self.tree = tree
    }

    func listTree() async throws -> FileTree {
        tree
    }

    func listArchivedTree(limit: Int, offset: Int) async throws -> FileTree {
        _ = limit
        _ = offset
        return FileTree(children: [])
    }

    func getNote(id: String) async throws -> NotePayload {
        _ = id
        throw StaticTreeAPIError.unused
    }

    func search(query: String, limit: Int) async throws -> [FileNode] {
        _ = query
        _ = limit
        return []
    }

    func updateNote(id: String, content: String) async throws -> NotePayload {
        _ = id
        _ = content
        throw StaticTreeAPIError.unused
    }

    func createNote(request: NoteCreateRequest) async throws -> NotePayload {
        _ = request
        throw StaticTreeAPIError.unused
    }

    func renameNote(id: String, newName: String) async throws -> NotePayload {
        _ = id
        _ = newName
        throw StaticTreeAPIError.unused
    }

    func moveNote(id: String, folder: String) async throws -> NotePayload {
        _ = id
        _ = folder
        throw StaticTreeAPIError.unused
    }

    func archiveNote(id: String, archived: Bool) async throws -> NotePayload {
        _ = id
        _ = archived
        throw StaticTreeAPIError.unused
    }

    func pinNote(id: String, pinned: Bool) async throws -> NotePayload {
        _ = id
        _ = pinned
        throw StaticTreeAPIError.unused
    }

    func updatePinnedOrder(ids: [String]) async throws {
        _ = ids
    }

    func deleteNote(id: String) async throws -> NotePayload {
        _ = id
        throw StaticTreeAPIError.unused
    }

    func createFolder(path: String) async throws {
        _ = path
    }

    func renameFolder(oldPath: String, newName: String) async throws {
        _ = oldPath
        _ = newName
    }

    func moveFolder(oldPath: String, newParent: String) async throws {
        _ = oldPath
        _ = newParent
    }

    func deleteFolder(path: String) async throws {
        _ = path
    }
}
