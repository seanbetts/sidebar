import XCTest
import SwiftUI

#if os(macOS)
import AppKit
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class SelectableNoteReadViewMountedMacOSTests: XCTestCase {
    func testMountedReadSurfaceCanUnmountRepeatedlyWithoutCrashing() throws {
        let document = NotesSemanticDocumentProjection.document(fromPlainText: "One\nTwo")

        for _ in 0..<notesLifetimeSmokeIterations {
            let controller = NSHostingController(
                rootView: AnyView(
                    SelectableNoteReadView(
                        document: document,
                        maxContentWidth: 420,
                        onActivateEditing: { _ in }
                    )
                )
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 240),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = controller
            window.orderFront(nil)
            _ = controller.view

            controller.rootView = AnyView(EmptyView())
            drainNotesHostingRunLoop()

            window.orderOut(nil)
            window.contentViewController = nil
            drainNotesHostingRunLoop()
        }
    }
}
#endif
