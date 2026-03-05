import XCTest
@testable import sideBar

@MainActor
final class NotesPanelTreeHelpersTests: XCTestCase {
    func testMainNodesSortUnpinnedNotesByMostRecentCreated() async {
        let tree = FileTree(children: [
            makeFile(path: "note-old", name: "Old.md", created: 100, modified: 500),
            makeFile(path: "note-pinned", name: "Pinned.md", created: 400, modified: 900, pinned: true, pinnedOrder: 0),
            makeFile(path: "note-new", name: "New.md", created: 300, modified: 200),
            makeFile(path: "note-mid", name: "Mid.md", created: 200, modified: 800)
        ])
        let viewModel = makeViewModel(tree: tree)

        await viewModel.loadTree()
        let panel = NotesPanelView(viewModel: viewModel)

        XCTAssertEqual(panel.mainNodes.map(\.path), ["note-new", "note-mid", "note-old"])
    }

    func testPinnedItemsUsePinnedOrderNotRecency() async {
        let tree = FileTree(children: [
            makeFile(path: "pin-first", name: "First.md", created: 100, modified: 100, pinned: true, pinnedOrder: 0),
            makeFile(path: "pin-second", name: "Second.md", created: 500, modified: 500, pinned: true, pinnedOrder: 2)
        ])
        let viewModel = makeViewModel(tree: tree)

        await viewModel.loadTree()
        let panel = NotesPanelView(viewModel: viewModel)

        XCTAssertEqual(panel.pinnedItems.map(\.id), ["pin-first", "pin-second"])
    }

    func testMainNodesSortFolderChildrenByMostRecentCreated() async {
        let folder = FileNode(
            name: "Work",
            path: "folder:Work",
            type: .directory,
            size: nil,
            modified: nil,
            created: nil,
            children: [
                makeFile(path: "work-old", name: "WorkOld.md", created: 100, modified: 900),
                makeFile(path: "work-new", name: "WorkNew.md", created: 200, modified: 1)
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

    func testArchivedNodesSortByMostRecentCreated() async {
        let archivedTree = FileTree(children: [
            makeFile(path: "arch-old", name: "Old.md", created: 100, modified: 500, archived: true),
            makeFile(path: "arch-new", name: "New.md", created: 300, modified: 200, archived: true),
            makeFile(path: "arch-mid", name: "Mid.md", created: 200, modified: 800, archived: true)
        ])
        let viewModel = makeViewModel(tree: FileTree(children: []), archivedTree: archivedTree)

        await viewModel.loadArchivedTree()
        let panel = NotesPanelView(viewModel: viewModel)

        XCTAssertEqual(panel.archivedNodes.map(\.path), ["arch-new", "arch-mid", "arch-old"])
    }

    func testNoteContextMenuIncludesShareTextForFileItems() {
        let item = FileNodeItem(id: "note-1", name: "Note.md", type: .file)

        let actions = NotesPanelView.noteContextMenuActions(for: item)

        XCTAssertTrue(actions.contains(.shareText))
        XCTAssertFalse(actions.contains(.rename))
    }

    func testFileNodeDisplayNamePreservesMarkdownLikeSuffixes() {
        let item = FileNodeItem(id: "note-1", name: "Note.md", type: .file)

        XCTAssertEqual(item.displayName, "Note.md")
    }

    func testNoteContextMenuDoesNotIncludeShareTextForFolderItems() {
        let item = FileNodeItem(id: "folder", name: "Folder", type: .directory)

        let actions = NotesPanelView.noteContextMenuActions(for: item)

        XCTAssertFalse(actions.contains(.shareText))
        XCTAssertTrue(actions.contains(.rename))
    }
}

@MainActor
private func makeViewModel(tree: FileTree, archivedTree: FileTree? = nil) -> NotesViewModel {
    let resolvedArchivedTree = archivedTree ?? FileTree(children: [])
    let api = StaticTreeNotesAPI(tree: tree, archivedTree: resolvedArchivedTree)
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
    created: Double?,
    modified: Double? = nil,
    pinned: Bool = false,
    pinnedOrder: Int? = nil,
    archived: Bool = false
) -> FileNode {
    FileNode(
        name: name,
        path: path,
        type: .file,
        size: nil,
        modified: modified,
        created: created,
        children: nil,
        expanded: nil,
        pinned: pinned,
        pinnedOrder: pinnedOrder,
        archived: archived,
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
    private let archivedTree: FileTree

    init(tree: FileTree, archivedTree: FileTree) {
        self.tree = tree
        self.archivedTree = archivedTree
    }

    func listTree() async throws -> FileTree {
        tree
    }

    func listArchivedTree(limit: Int, offset: Int) async throws -> FileTree {
        _ = limit
        _ = offset
        return archivedTree
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
