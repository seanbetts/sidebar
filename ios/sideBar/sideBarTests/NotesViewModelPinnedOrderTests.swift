import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class NotesViewModelPinnedOrderTests: XCTestCase {
    func testReorderPinnedNotesOptimisticallyUpdatesStoreAndCallsAPI() async {
        let api = NotesPinnedOrderAPISpy()
        api.updatePinnedOrderResult = .success(())
        let cache = InMemoryCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let toastCenter = ToastCenter()
        let viewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toastCenter,
            networkStatus: NotesPinnedOrderTestNetworkStatus(isNetworkAvailable: true)
        )
        store.applyTreeUpdate(makePinnedTree(), persist: false)

        let success = await viewModel.reorderPinnedNotes(ids: ["/b.md", "/a.md"])

        XCTAssertTrue(success)
        XCTAssertEqual(api.updatedPinnedOrderIDs, [["/b.md", "/a.md"]])
        XCTAssertEqual(currentPinnedOrder(in: viewModel.tree), ["/b.md", "/a.md"])
    }

    func testReorderPinnedNotesRollsBackAndShowsToastWhenAPIFails() async {
        let api = NotesPinnedOrderAPISpy()
        api.updatePinnedOrderResult = .failure(NotesPinnedOrderMockError.forced)
        let cache = InMemoryCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let toastCenter = ToastCenter()
        let viewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toastCenter,
            networkStatus: NotesPinnedOrderTestNetworkStatus(isNetworkAvailable: true)
        )
        store.applyTreeUpdate(makePinnedTree(), persist: false)
        await waitUntil(timeout: .milliseconds(200)) {
            currentPinnedOrder(in: viewModel.tree) == ["/a.md", "/b.md"]
        }
        let previousOrder = currentPinnedOrder(in: viewModel.tree)

        let success = await viewModel.reorderPinnedNotes(ids: ["/b.md", "/a.md"])

        XCTAssertFalse(success)
        XCTAssertEqual(currentPinnedOrder(in: viewModel.tree), previousOrder)
        XCTAssertEqual(toastCenter.toast?.message, "Failed to reorder pinned notes")
    }

    func testReorderPinnedNotesDoesNotCallAPIWhenOffline() async {
        let api = NotesPinnedOrderAPISpy()
        api.updatePinnedOrderResult = .success(())
        let cache = InMemoryCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let toastCenter = ToastCenter()
        let viewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toastCenter,
            networkStatus: NotesPinnedOrderTestNetworkStatus(isNetworkAvailable: false)
        )

        let success = await viewModel.reorderPinnedNotes(ids: ["/b.md", "/a.md"])

        XCTAssertFalse(success)
        XCTAssertEqual(api.updatePinnedOrderCallCount, 0)
    }

    func testReorderPinnedNotesRejectsStalePinnedSetWithoutCallingAPI() async {
        let api = NotesPinnedOrderAPISpy()
        api.updatePinnedOrderResult = .success(())
        let cache = InMemoryCacheClient()
        let store = NotesStore(api: api, cache: cache)
        let toastCenter = ToastCenter()
        let viewModel = NotesViewModel(
            api: api,
            store: store,
            toastCenter: toastCenter,
            networkStatus: NotesPinnedOrderTestNetworkStatus(isNetworkAvailable: true)
        )
        store.applyTreeUpdate(makePinnedTree(), persist: false)
        let previousOrder = currentPinnedOrder(in: viewModel.tree)

        let success = await viewModel.reorderPinnedNotes(ids: ["/b.md"])

        XCTAssertFalse(success)
        XCTAssertEqual(api.updatePinnedOrderCallCount, 0)
        XCTAssertEqual(currentPinnedOrder(in: viewModel.tree), previousOrder)
    }

    private func makePinnedTree() -> FileTree {
        FileTree(children: [
            FileNode(
                name: "A.md",
                path: "/a.md",
                type: .file,
                size: nil,
                modified: nil,
                created: nil,
                children: nil,
                expanded: nil,
                pinned: true,
                pinnedOrder: 0,
                archived: false,
                folderMarker: nil
            ),
            FileNode(
                name: "B.md",
                path: "/b.md",
                type: .file,
                size: nil,
                modified: nil,
                created: nil,
                children: nil,
                expanded: nil,
                pinned: true,
                pinnedOrder: 1,
                archived: false,
                folderMarker: nil
            )
        ])
    }
}

private enum NotesPinnedOrderMockError: Error {
    case forced
}

@MainActor
private struct NotesPinnedOrderTestNetworkStatus: NetworkStatusProviding {
    let isNetworkAvailable: Bool
    let isOffline: Bool

    init(isNetworkAvailable: Bool, isOffline: Bool = false) {
        self.isNetworkAvailable = isNetworkAvailable
        self.isOffline = isOffline
    }
}

@MainActor
private final class NotesPinnedOrderAPISpy: NotesProviding {
    var updatePinnedOrderCallCount = 0
    var updatedPinnedOrderIDs: [[String]] = []
    var updatePinnedOrderResult: Result<Void, Error> = .success(())

    func listTree() async throws -> FileTree {
        throw NotesPinnedOrderMockError.forced
    }

    func listArchivedTree(limit: Int, offset: Int) async throws -> FileTree {
        _ = limit
        _ = offset
        throw NotesPinnedOrderMockError.forced
    }

    func getNote(id: String) async throws -> NotePayload {
        _ = id
        throw NotesPinnedOrderMockError.forced
    }

    func search(query: String, limit: Int) async throws -> [FileNode] {
        _ = query
        _ = limit
        return []
    }

    func updateNote(id: String, content: String) async throws -> NotePayload {
        _ = id
        _ = content
        throw NotesPinnedOrderMockError.forced
    }

    func updateNote(id: String, document: NotesSemanticDocument) async throws -> NotePayload {
        try await updateNote(
            id: id,
            content: NotesSemanticDocumentProjection.plainText(from: document)
        )
    }

    func createNote(request: NoteCreateRequest) async throws -> NotePayload {
        _ = request
        throw NotesPinnedOrderMockError.forced
    }

    func moveNote(id: String, folder: String) async throws -> NotePayload {
        _ = id
        _ = folder
        throw NotesPinnedOrderMockError.forced
    }

    func archiveNote(id: String, archived: Bool) async throws -> NotePayload {
        _ = id
        _ = archived
        throw NotesPinnedOrderMockError.forced
    }

    func pinNote(id: String, pinned: Bool) async throws -> NotePayload {
        _ = id
        _ = pinned
        throw NotesPinnedOrderMockError.forced
    }

    func updatePinnedOrder(ids: [String]) async throws {
        updatePinnedOrderCallCount += 1
        updatedPinnedOrderIDs.append(ids)
        try updatePinnedOrderResult.get()
    }

    func deleteNote(id: String) async throws -> NotePayload {
        _ = id
        throw NotesPinnedOrderMockError.forced
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

private func currentPinnedOrder(in tree: FileTree?) -> [String] {
    guard let tree else { return [] }
    return pinnedNodes(in: tree.children)
        .sorted {
            let leftOrder = $0.pinnedOrder ?? Int.max
            let rightOrder = $1.pinnedOrder ?? Int.max
            if leftOrder != rightOrder {
                return leftOrder < rightOrder
            }
            return $0.path < $1.path
        }
        .map(\.path)
}

private func pinnedNodes(in nodes: [FileNode]) -> [FileNode] {
    var results: [FileNode] = []
    for node in nodes {
        if node.type == .file, node.pinned == true {
            results.append(node)
        }
        if let children = node.children {
            results.append(contentsOf: pinnedNodes(in: children))
        }
    }
    return results
}
