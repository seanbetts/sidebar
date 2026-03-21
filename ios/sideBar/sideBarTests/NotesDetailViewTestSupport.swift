import SwiftUI
import XCTest
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif
import sideBarShared
@testable import sideBar
// Keep the fast lane to a few lifetime cycles; the longer mixed teardown soak remains quarantined in the mounted macOS repro suite.
let notesLifetimeSmokeIterations = 4
private let notesHostingDrainDuration: TimeInterval = 0.01
@MainActor
struct NotesDetailViewTestContext {
    let store: NotesStore
    let notesViewModel: NotesViewModel
    let editorViewModel: NotesEditorViewModel
    func makeView() -> NotesDetailView {
        NotesDetailView(
            viewModel: notesViewModel,
            editorViewModel: editorViewModel,
            isMoveSheetPresented: .constant(false),
            moveSelection: .constant(""),
            isDeleteAlertPresented: .constant(false),
            isExporting: .constant(false),
            exportDocument: .constant(nil),
            exportFilename: .constant("")
        )
    }
}
@MainActor
enum NotesDetailViewTestRetainer {
    static var environments: [AppEnvironment] = []
    #if os(macOS)
    static var hostingControllers: [NSHostingController<AnyView>] = []
    static var hostingWindows: [NSWindow] = []
    #elseif os(iOS)
    struct ParkedHostBatch {
        let environments: [AppEnvironment]
        let hostingControllers: [UIHostingController<AnyView>]
        let hostingWindows: [UIWindow]
    }
    static var hostingControllers: [UIHostingController<AnyView>] = []
    static var hostingWindows: [UIWindow] = []
    static var parkedHostBatches: [ParkedHostBatch] = []
    #endif
    static func reset() {
        #if os(iOS)
        drainNotesHostingRunLoop()
        hostingWindows.forEach { window in
            window.endEditing(true)
            window.resignKey()
            window.isHidden = true
        }
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { candidate in
                hostingWindows.contains { window in window === candidate } == false
            }?
            .makeKey()
        drainNotesHostingRunLoop()
        let parkedBatch = ParkedHostBatch(
            environments: environments,
            hostingControllers: hostingControllers,
            hostingWindows: hostingWindows
        )
        hostingWindows.forEach { window in
            if let controller = window.rootViewController as? UIHostingController<AnyView> {
                controller.rootView = AnyView(EmptyView())
                controller.view.removeFromSuperview()
            } else {
                window.rootViewController?.view.removeFromSuperview()
            }
            window.rootViewController = nil
            window.windowScene = nil
        }
        drainNotesHostingRunLoop()
        if parkedBatch.environments.isEmpty == false
            || parkedBatch.hostingControllers.isEmpty == false
            || parkedBatch.hostingWindows.isEmpty == false {
            parkedHostBatches.append(parkedBatch)
        }
        AppEnvironment.shared = nil
        hostingControllers.removeAll()
        hostingWindows.removeAll()
        drainNotesHostingRunLoop()
        #elseif os(macOS)
        hostingWindows.forEach { window in
            window.orderOut(nil)
            window.contentViewController = nil
        }
        drainNotesHostingRunLoop()
        hostingControllers.removeAll()
        hostingWindows.removeAll()
        drainNotesHostingRunLoop()
        #endif
        environments.removeAll()
    }
}
@MainActor
class NotesDetailViewHostingTestCase: XCTestCase {
    override func tearDown() {
        NotesDetailViewTestRetainer.reset()
        super.tearDown()
    }
}
@MainActor
func makeNotesDetailViewTestContext(
    note: NotePayload = makeTestNote(),
    api: any NotesProviding = NotesDetailViewRecordingNotesAPI()
) async -> NotesDetailViewTestContext {
    let store = NotesStore(api: api, cache: InMemoryCacheClient())
    let notesViewModel = NotesViewModel(
        api: api,
        store: store,
        toastCenter: ToastCenter(),
        networkStatus: NotesDetailViewTestNetworkStatus(isNetworkAvailable: true)
    )
    let persistence = PersistenceController(inMemory: true)
    let editorViewModel = NotesEditorViewModel(
        notesViewModel: notesViewModel,
        draftStorage: DraftStorage(container: persistence.container),
        writeQueue: WriteQueue(
            container: persistence.container,
            connectivityMonitor: ConnectivityMonitor(
                baseUrl: URL(string: "http://localhost")!,
                startMonitoring: false
            ),
            autoProcessEnabled: false
        ),
        networkStatus: NotesDetailViewTestNetworkStatus(isNetworkAvailable: true)
    )
    store.applyEditorUpdate(note)
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async {
            continuation.resume()
        }
    }
    return NotesDetailViewTestContext(
        store: store,
        notesViewModel: notesViewModel,
        editorViewModel: editorViewModel
    )
}
@MainActor
func makeNotesDetailTestEnvironment(
    retainInGlobalRetainer: Bool = true
) -> AppEnvironment {
    let container = ServiceContainer(
        config: .fallbackForTesting(),
        authSession: NotesDetailViewTestAuthSession(),
        cacheClient: InMemoryCacheClient()
    )
    let environment = AppEnvironment(container: container)
    if retainInGlobalRetainer {
        NotesDetailViewTestRetainer.environments.append(environment)
    }
    return environment
}
#if os(macOS)
@MainActor
@discardableResult
func mount(
    _ view: some View,
    frame: CGRect = CGRect(x: 0, y: 0, width: 900, height: 700)
) -> NSHostingController<AnyView> {
    let controller = NSHostingController(
        rootView: AnyView(view)
    )
    let window = NSWindow(
        contentRect: frame,
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    window.contentViewController = controller
    window.makeKeyAndOrderFront(nil)
    let rootView = controller.view
    rootView.frame = frame
    rootView.layoutSubtreeIfNeeded()
    window.contentView?.layoutSubtreeIfNeeded()
    drainNotesHostingRunLoop()
    NotesDetailViewTestRetainer.hostingControllers.append(controller)
    NotesDetailViewTestRetainer.hostingWindows.append(window)
    return controller
}
@MainActor
@discardableResult
func mount(
    _ view: NotesDetailView,
    environment: AppEnvironment
) -> NSHostingController<AnyView> {
    mount(
        view.environmentObject(environment),
        frame: CGRect(x: 0, y: 0, width: 900, height: 700)
    )
}
#elseif os(iOS)
@MainActor
@discardableResult
func mount(
    _ view: some View,
    frame: CGRect = CGRect(x: 0, y: 0, width: 390, height: 844),
    makeKeyAndVisible: Bool = false
) -> UIHostingController<AnyView> {
    let controller = UIHostingController(
        rootView: AnyView(view)
    )
    let window = makeHostingWindow(frame: frame)
    window.rootViewController = controller
    if makeKeyAndVisible {
        window.makeKeyAndVisible()
    } else {
        window.isHidden = false
    }
    let rootView = controller.view!
    rootView.frame = frame
    rootView.setNeedsLayout()
    rootView.layoutIfNeeded()
    drainNotesHostingRunLoop()
    NotesDetailViewTestRetainer.hostingControllers.append(controller)
    NotesDetailViewTestRetainer.hostingWindows.append(window)
    return controller
}
@MainActor
@discardableResult
func mount(
    _ view: NotesDetailView,
    environment: AppEnvironment,
    makeKeyAndVisible: Bool = false
) -> UIHostingController<AnyView> {
    mount(
        view.environmentObject(environment),
        frame: CGRect(x: 0, y: 0, width: 900, height: 700),
        makeKeyAndVisible: makeKeyAndVisible
    )
}
@MainActor
@discardableResult
func mount(
    _ container: AttributedNoteEditorContainer,
    environment: AppEnvironment,
    frame: CGRect = CGRect(x: 0, y: 0, width: 390, height: 844)
) -> UIHostingController<AnyView> {
    mount(container.environmentObject(environment), frame: frame)
}

@MainActor
private func makeHostingWindow(frame: CGRect) -> UIWindow {
    guard let windowScene = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first else {
        fatalError("Expected UIWindowScene for mounted notes detail tests")
    }

    let window = UIWindow(windowScene: windowScene)
    window.frame = frame
    return window
}
#endif

@MainActor
func drainNotesHostingRunLoop() {
    RunLoop.main.run(until: Date().addingTimeInterval(notesHostingDrainDuration))
}

func makeTestNote(
    id: String = "n1",
    name: String = "Semantic title",
    plainText: String = "Hello world",
    path: String = "/note.md"
) -> NotePayload {
    let document = NotesSemanticDocumentProjection.document(fromPlainText: plainText)
    return NotePayload(
        id: id,
        name: name,
        document: document,
        plainText: plainText,
        path: path,
        modified: nil,
        created: nil
    )
}

@MainActor
struct NotesDetailViewTestNetworkStatus: NetworkStatusProviding {
    let isNetworkAvailable: Bool
    let isOffline: Bool = false
}

final class NotesDetailViewRecordingNotesAPI: NotesProviding {
    private(set) var updateCallCount = 0

    func listTree() async throws -> FileTree { FileTree(children: []) }
    func listArchivedTree(limit: Int, offset: Int) async throws -> FileTree {
        _ = limit
        _ = offset
        return FileTree(children: [])
    }

    func getNote(id: String) async throws -> NotePayload {
        _ = id
        throw NotesDetailViewTestError.forced
    }

    func search(query: String, limit: Int) async throws -> [FileNode] {
        _ = query
        _ = limit
        return []
    }

    func updateNote(id: String, content: String) async throws -> NotePayload {
        _ = id
        _ = content
        throw NotesDetailViewTestError.forced
    }

    func updateNote(id: String, document: NotesSemanticDocument) async throws -> NotePayload {
        updateCallCount += 1
        return NotePayload(
            id: id,
            name: "Semantic title",
            document: document,
            plainText: NotesSemanticDocumentProjection.plainText(from: document),
            path: "/note.md",
            modified: 100,
            created: nil
        )
    }

    func createNote(request: NoteCreateRequest) async throws -> NotePayload {
        _ = request
        throw NotesDetailViewTestError.forced
    }

    func moveNote(id: String, folder: String) async throws -> NotePayload {
        _ = id
        _ = folder
        throw NotesDetailViewTestError.forced
    }

    func archiveNote(id: String, archived: Bool) async throws -> NotePayload {
        _ = id
        _ = archived
        throw NotesDetailViewTestError.forced
    }

    func pinNote(id: String, pinned: Bool) async throws -> NotePayload {
        _ = id
        _ = pinned
        throw NotesDetailViewTestError.forced
    }

    func updatePinnedOrder(ids: [String]) async throws {
        _ = ids
    }

    func deleteNote(id: String) async throws -> NotePayload {
        _ = id
        throw NotesDetailViewTestError.forced
    }

    func createFolder(path: String) async throws { _ = path }
    func renameFolder(oldPath: String, newName: String) async throws {
        _ = oldPath
        _ = newName
    }
    func moveFolder(oldPath: String, newParent: String) async throws {
        _ = oldPath
        _ = newParent
    }
    func deleteFolder(path: String) async throws { _ = path }
}

final class NotesDetailViewFailingNotesAPI: NotesProviding {
    func listTree() async throws -> FileTree { FileTree(children: []) }
    func listArchivedTree(limit: Int, offset: Int) async throws -> FileTree {
        _ = limit
        _ = offset
        return FileTree(children: [])
    }

    func getNote(id: String) async throws -> NotePayload {
        _ = id
        throw NotesDetailViewTestError.forced
    }

    func search(query: String, limit: Int) async throws -> [FileNode] {
        _ = query
        _ = limit
        return []
    }

    func updateNote(id: String, content: String) async throws -> NotePayload {
        _ = id
        _ = content
        throw NotesDetailViewTestError.forced
    }

    func updateNote(id: String, document: NotesSemanticDocument) async throws -> NotePayload {
        _ = id
        _ = document
        throw NotesDetailViewTestError.forced
    }

    func createNote(request: NoteCreateRequest) async throws -> NotePayload {
        _ = request
        throw NotesDetailViewTestError.forced
    }

    func moveNote(id: String, folder: String) async throws -> NotePayload {
        _ = id
        _ = folder
        throw NotesDetailViewTestError.forced
    }

    func archiveNote(id: String, archived: Bool) async throws -> NotePayload {
        _ = id
        _ = archived
        throw NotesDetailViewTestError.forced
    }

    func pinNote(id: String, pinned: Bool) async throws -> NotePayload {
        _ = id
        _ = pinned
        throw NotesDetailViewTestError.forced
    }

    func updatePinnedOrder(ids: [String]) async throws {
        _ = ids
    }

    func deleteNote(id: String) async throws -> NotePayload {
        _ = id
        throw NotesDetailViewTestError.forced
    }

    func createFolder(path: String) async throws { _ = path }
    func renameFolder(oldPath: String, newName: String) async throws {
        _ = oldPath
        _ = newName
    }
    func moveFolder(oldPath: String, newParent: String) async throws {
        _ = oldPath
        _ = newParent
    }
    func deleteFolder(path: String) async throws { _ = path }
}

final class NotesDetailViewTestAuthSession: AuthSession {
    var accessToken: String?
    var userId: String?
    var authState: AuthState = .signedOut

    var authorizationToken: String? {
        authState == .active ? accessToken : nil
    }

    func signIn(email: String, password: String) async throws {
        _ = email
        _ = password
        authState = .active
    }

    func refreshSession() async {
    }

    func refreshSessionIfStale() async {
    }

    func signOut() async {
        accessToken = nil
        userId = nil
        authState = .signedOut
    }
}

enum NotesDetailViewTestError: Error {
    case forced
}

@MainActor
func waitUntil(
    timeout: Duration = .seconds(1),
    pollInterval: Duration = .milliseconds(10),
    file: StaticString = #filePath,
    line: UInt = #line,
    condition: @escaping @MainActor () -> Bool
) async {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !condition() {
        if clock.now >= deadline {
            XCTFail("Timed out waiting for condition", file: file, line: line)
            return
        }
        try? await Task.sleep(for: pollInterval)
    }
}
