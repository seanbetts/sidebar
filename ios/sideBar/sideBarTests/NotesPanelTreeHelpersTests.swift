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

        XCTAssertEqual(panel.pinnedItems.map { $0.id }, ["pin-first", "pin-second"])
    }

    func testPinnedItemsReflectLocallyUpdatedPinnedOrder() async {
        let initialTree = FileTree(children: [
            makeFile(path: "note-a", name: "A.md", created: 100, pinned: true, pinnedOrder: 0),
            makeFile(path: "note-b", name: "B.md", created: 200, pinned: true, pinnedOrder: 1)
        ])
        let fixture = makeViewModelAndStore(tree: initialTree)
        let viewModel = fixture.viewModel
        let store = fixture.store

        await viewModel.loadTree()
        let panel = NotesPanelView(viewModel: viewModel)

        let updatedTree = FileTree(children: [
            makeFile(path: "note-a", name: "A.md", created: 100, pinned: true, pinnedOrder: 1),
            makeFile(path: "note-b", name: "B.md", created: 200, pinned: true, pinnedOrder: 0)
        ])
        store.applyTreeUpdate(updatedTree, persist: false)

        await waitUntil(timeout: .milliseconds(200)) {
            panel.pinnedItems.map { $0.id } == ["note-b", "note-a"]
        }
        XCTAssertEqual(panel.pinnedItems.map { $0.id }, ["note-b", "note-a"])
    }

    func testPinnedReorderAffordancesRequireAtLeastTwoPinnedNotes() async {
        let panel = await makeView(
            tree: FileTree(children: [
                makeFile(path: "note-a", name: "A.md", created: 100, pinned: true, pinnedOrder: 0)
            ])
        )

        XCTAssertFalse(panel.canStartPinnedReorder)
        XCTAssertFalse(panel.isPinnedReorderEditActive)
    }

    func testPinnedReorderShowsMoveHandlesWheneverPinnedSectionCanReorder() async {
        let view = await makeView()

        XCTAssertTrue(view.isPinnedReorderEditActive)
    }

    func testPinnedReorderLifecycleHelpersTrackCurrentInteraction() async {
        let view = await makeView()

        XCTAssertFalse(view.isPinnedReordering)

        view.enterPinnedReorder(from: "note-a")
        XCTAssertTrue(view.isPinnedReordering)
        XCTAssertEqual(view.pinnedReorderSourceID, "note-a")
        XCTAssertTrue(view.isPinnedReorderEditActive)

        view.completePinnedReorder()
        XCTAssertFalse(view.isPinnedReordering)
        XCTAssertNil(view.pinnedReorderSourceID)
        XCTAssertTrue(view.isPinnedReorderEditActive)

        view.enterPinnedReorder(from: "note-a")
        view.cancelPinnedReorder()
        XCTAssertFalse(view.isPinnedReordering)
        XCTAssertTrue(view.isPinnedReorderEditActive)
    }

    func testPinnedReorderCancelsWhenPinnedSetChangesMidGesture() async {
        let view = await makeView()

        view.enterPinnedReorder(from: "note-a")
        view.handlePinnedSetChanged(["note-b"])

        XCTAssertFalse(view.isPinnedReordering)
    }

    func testPinnedReorderRejectsOfflineActivation() async {
        let offlineView = await makeView(isNetworkAvailable: false)

        XCTAssertFalse(offlineView.canStartPinnedReorder)
        XCTAssertFalse(offlineView.isPinnedReorderEditActive)
    }

    func testPinnedReorderMoveKeepsSessionActiveUntilTimeoutAndPersistsFinalOrder() async {
        let (view, api) = await makeViewWithAPI(autoExitDelay: 0.05)

        view.enterPinnedReorder(from: "note-a")
        view.movePinnedNotes(from: IndexSet(integer: 0), to: 2)

        XCTAssertTrue(view.isPinnedReordering)
        XCTAssertEqual(view.pinnedItems.map { $0.id }, ["note-b", "note-a"])
        XCTAssertEqual(api.updatePinnedOrderCallCount, 0)

        try? await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertFalse(view.isPinnedReordering)
        XCTAssertEqual(api.updatePinnedOrderCallCount, 1)
        XCTAssertEqual(api.lastPinnedOrderIDs, ["note-b", "note-a"])
    }

    func testPinnedReorderDropTargetsRejectNonPinnedOrCrossSectionItems() async {
        let view = await makeView()

        XCTAssertFalse(
            view.canAcceptPinnedDrop(
                isPinned: false,
                sourceSection: .mainNotes,
                destinationSection: .pinned
            )
        )
        XCTAssertFalse(
            view.canAcceptPinnedDrop(
                isPinned: true,
                sourceSection: .mainNotes,
                destinationSection: .pinned
            )
        )
        XCTAssertFalse(
            view.canAcceptPinnedDrop(
                isPinned: true,
                sourceSection: .pinned,
                destinationSection: .mainNotes
            )
        )
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

    func testSectionOrderOmitsArchiveWhenNoArchivedContentExists() async {
        let viewModel = makeViewModel(tree: FileTree(children: []), archivedTree: FileTree(children: []))

        await viewModel.loadTree()
        await viewModel.loadArchivedTree()
        let panel = NotesPanelView(viewModel: viewModel)

        XCTAssertEqual(panel.listSectionLayout, [])
    }

    func testSectionOrderShowsSparseStateThenArchiveWhenOnlyArchiveRemains() async {
        let archivedTree = FileTree(children: [
            makeFile(path: "archived-note", name: "Archived.md", created: 100, archived: true)
        ])
        let viewModel = makeViewModel(tree: FileTree(children: []), archivedTree: archivedTree)

        await viewModel.loadTree()
        await viewModel.loadArchivedTree()
        let panel = NotesPanelView(viewModel: viewModel)

        XCTAssertEqual(panel.listSectionLayout, [.sparseState, .archive])
    }

    func testSectionOrderShowsPinnedAndMainWithoutArchiveWhenNothingIsArchived() async {
        let tree = FileTree(children: [makeFile(path: "note-1", name: "Note.md", created: 100)])
        let viewModel = makeViewModel(tree: tree, archivedTree: FileTree(children: []))

        await viewModel.loadTree()
        await viewModel.loadArchivedTree()
        let panel = NotesPanelView(viewModel: viewModel)

        XCTAssertEqual(panel.listSectionLayout, [.pinned, .mainNotes])
    }

    func testNoteContextMenuIncludesShareTextForFileItems() {
        let item = FileNodeItem(id: "note-1", name: "Note.md", type: .file)

        let actions = NotesPanelView.noteContextMenuActions(for: item)

        XCTAssertTrue(actions.contains(.shareText))
        XCTAssertFalse(actions.contains(.rename))
    }

    func testPinnedNoteContextMenuDoesNotIncludeReorderWhenHandlesAreAlwaysVisible() async {
        let view = await makeView()
        let item = view.pinnedItems[0]

        let titles = view.noteContextMenuItemsList(for: item).map(\.title)

        XCTAssertFalse(titles.contains("Reorder"))
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

    func testSelectionRequestAlwaysSelectsOnCompactPhone() {
        XCTAssertEqual(
            NotesPanelView.selectionRequestAction(
                isCompactPhone: true,
                currentSelectedNoteId: "note-1",
                activeNoteId: "note-1",
                requestedNoteId: "note-2"
            ),
            .select
        )
    }

    func testSelectionRequestIgnoresAlreadyOpenNoteOffCompactPhone() {
        XCTAssertEqual(
            NotesPanelView.selectionRequestAction(
                isCompactPhone: false,
                currentSelectedNoteId: "note-1",
                activeNoteId: "note-1",
                requestedNoteId: "note-1"
            ),
            .ignore
        )
    }
}

@MainActor
private func makeViewModel(tree: FileTree, archivedTree: FileTree? = nil) -> NotesViewModel {
    makeViewModelAndStore(tree: tree, archivedTree: archivedTree).viewModel
}

@MainActor
private func makeViewModelAndStore(
    tree: FileTree,
    archivedTree: FileTree? = nil
) -> NotesPanelTestFixture {
    let resolvedArchivedTree = archivedTree ?? FileTree(children: [])
    let api = StaticTreeNotesAPI(tree: tree, archivedTree: resolvedArchivedTree)
    let store = NotesStore(api: api, cache: InMemoryCacheClient())
    let viewModel = NotesViewModel(
        api: api,
        store: store,
        toastCenter: ToastCenter(),
        networkStatus: PanelTestNetworkStatus(isNetworkAvailable: true)
    )
    return NotesPanelTestFixture(viewModel: viewModel, store: store, api: api)
}

@MainActor
private func makeView(
    isNetworkAvailable: Bool = true,
    tree: FileTree? = nil
) async -> NotesPanelView {
    let (view, _) = await makeViewWithAPI(
        isNetworkAvailable: isNetworkAvailable,
        tree: tree
    )
    return view
}

@MainActor
private func makeViewWithAPI(
    isNetworkAvailable: Bool = true,
    tree: FileTree? = nil,
    autoExitDelay: TimeInterval? = nil
) async -> (NotesPanelView, StaticTreeNotesAPI) {
    let resolvedTree = tree ?? FileTree(children: [
        makeFile(path: "note-a", name: "A.md", created: 100, pinned: true, pinnedOrder: 0),
        makeFile(path: "note-b", name: "B.md", created: 200, pinned: true, pinnedOrder: 1)
    ])
    let fixture = makeViewModelAndStore(tree: resolvedTree)
    let viewModel = fixture.viewModel
    let api = fixture.api
    await viewModel.loadTree()
    let view = NotesPanelView(
        viewModel: viewModel,
        pinnedReorderNetworkAvailability: isNetworkAvailable,
        pinnedReorderAutoExitDelay: autoExitDelay
    )
    return (view, api)
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

private struct NotesPanelTestFixture {
    let viewModel: NotesViewModel
    let store: NotesStore
    let api: StaticTreeNotesAPI
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
    private(set) var updatePinnedOrderCallCount = 0
    private(set) var lastPinnedOrderIDs: [String] = []

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

    func updateNote(id: String, document: NotesSemanticDocument) async throws -> NotePayload {
        try await updateNote(
            id: id,
            content: NotesSemanticDocumentProjection.plainText(from: document)
        )
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
        updatePinnedOrderCallCount += 1
        lastPinnedOrderIDs = ids
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
