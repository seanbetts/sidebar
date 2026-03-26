#if os(macOS)
import AppKit
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class AppKitEditorWindowEntryTests: XCTestCase {
    func testEditorTextViewAppliesReadableInsetWhenMovedToWindowBeforeFirstLayout() {
        let frame = NSRect(x: 0, y: 0, width: 1000, height: 320)
        let textView = AppKitNoteTextEditorSurface.EditorTextView(frame: frame)
        textView.maxReadableContentWidth = 800
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true

        let scrollView = NSScrollView(frame: frame)
        scrollView.documentView = textView

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = scrollView

        let expectedHorizontalInset = NoteTextLayout.horizontalPadding + ((frame.width - 800) / 2)

        XCTAssertEqual(textView.textContainerInset.width, expectedHorizontalInset, accuracy: 0.5)
        XCTAssertEqual(textView.textContainerInset.height, NoteTextLayout.verticalPadding, accuracy: 0.5)
    }
}
#endif
