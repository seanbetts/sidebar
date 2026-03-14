#if os(macOS)
import AVKit
import AppKit
import SwiftUI
import XCTest
@testable import sideBar

@MainActor
    @available(iOS 26.0, macOS 26.0, *)
final class FileViewerMountedMacOSTests: XCTestCase {
    func testMountedNativeVideoPlayerCanOpenRepeatedlyWithoutCrashing() {
        for _ in 0..<notesLifetimeSmokeIterations {
            let controller = NSHostingController(
                rootView: AnyView(
                    NativeVideoPlayer(player: AVPlayer())
                )
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
            drainNotesHostingRunLoop()

            controller.rootView = AnyView(EmptyView())
            drainNotesHostingRunLoop()

            window.orderOut(nil)
            window.contentViewController = nil
            drainNotesHostingRunLoop()
        }
    }
}
#endif
