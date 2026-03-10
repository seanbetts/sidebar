import SwiftUI
import XCTest

#if os(macOS)
import AppKit
@testable import sideBar

@MainActor
final class MountedNotesDetailHarness {
    private struct ParkedHost {
        let context: NotesDetailViewTestContext
        let environment: AppEnvironment
        let nativeEditorViewModel: NativeNoteEditorViewModel?
        let hostingController: NSHostingController<AnyView>
        let window: NSWindow
    }

    private static var parkedHosts: [ParkedHost] = []

    private var retainedContext: NotesDetailViewTestContext?
    private var retainedEnvironment: AppEnvironment?
    private var retainedNativeEditorViewModel: NativeNoteEditorViewModel?
    private var hostingController: NSHostingController<AnyView>?
    private var window: NSWindow?

    var context: NotesDetailViewTestContext {
        guard let retainedContext else {
            fatalError("MountedNotesDetailHarness context accessed after dispose")
        }
        return retainedContext
    }

    var environment: AppEnvironment {
        guard let retainedEnvironment else {
            fatalError("MountedNotesDetailHarness environment accessed after dispose")
        }
        return retainedEnvironment
    }

    init(
        note: NotePayload = makeTestNote(),
        api: any NotesProviding = NotesDetailViewRecordingNotesAPI()
    ) async {
        retainedContext = await makeNotesDetailViewTestContext(note: note, api: api)
        retainedEnvironment = makeNotesDetailTestEnvironment(retainInGlobalRetainer: false)
    }

    func mount() {
        let controller = NSHostingController(
            rootView: AnyView(context.makeView().environmentObject(environment))
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        window.orderFront(nil)
        _ = controller.view
        hostingController = controller
        self.window = window
    }

    func settle() async {
        await Task.yield()
        drainNotesHostingRunLoop()
    }

    func emitCloseShortcut() {
        environment.emitShortcutAction(.closeItem)
    }

    @available(iOS 26.0, macOS 26.0, *)
    func activateReadSurfaceEditing(
        at target: NotesEditorViewModel.PendingEditSelectionTarget
    ) -> NativeNoteEditorViewModel {
        let nativeViewModel = context.editorViewModel.makeNativeEditorViewModel()
        context.editorViewModel.attachNativeEditor(nativeViewModel)
        context.makeView().activateReadSurfaceEditing(at: target)
        _ = AttributedNoteEditorContainer.loadNoteIfNeeded(
            editorViewModel: context.editorViewModel,
            nativeViewModel: nativeViewModel,
            loadedNoteId: nil
        )
        retainedNativeEditorViewModel = nativeViewModel
        return nativeViewModel
    }

    func dispose() {
        if #available(iOS 26.0, macOS 26.0, *),
           let retainedNativeEditorViewModel {
            context.editorViewModel.detachNativeEditor(retainedNativeEditorViewModel)
            drainNotesHostingRunLoop()
        }
        guard let retainedContext,
              let retainedEnvironment,
              let hostingController,
              let window else {
            return
        }

        // Parking avoids a macOS XCTest/AppKit teardown crash in NSTextView
        // deallocation while still letting the test exercise repeated mounted
        // note interactions in fresh windows.
        window.makeFirstResponder(nil)
        window.orderOut(nil)
        Self.parkedHosts.append(
            ParkedHost(
                context: retainedContext,
                environment: retainedEnvironment,
                nativeEditorViewModel: retainedNativeEditorViewModel,
                hostingController: hostingController,
                window: window
            )
        )

        self.retainedNativeEditorViewModel = nil
        self.hostingController = nil
        self.window = nil
        self.retainedEnvironment = nil
        self.retainedContext = nil
    }
}
#endif
