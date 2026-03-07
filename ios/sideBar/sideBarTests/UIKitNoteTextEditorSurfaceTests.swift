#if os(iOS)
import SwiftUI
import UIKit
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, *)
final class UIKitNoteTextEditorSurfaceTests: XCTestCase {
    func testMountedNotesEditorUsesDedicatedUIKitTextViewHostOnIOS() async throws {
        let context = await makeNotesDetailViewTestContext(note: makeTestNote(plainText: "Hello"))
        context.editorViewModel.enterEditMode()

        let environment = makeNotesDetailTestEnvironment()
        let controller = mount(context.makeView(), environment: environment)
        await Task.yield()
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        let noteEditorTextView = findSubview(in: controller.view) { view in
            String(reflecting: type(of: view)).contains("NoteEditorTextView")
        }

        XCTAssertNotNil(noteEditorTextView)
    }
}

@MainActor
private func findSubview(
    in root: UIView,
    where predicate: (UIView) -> Bool
) -> UIView? {
    if predicate(root) {
        return root
    }

    for subview in root.subviews {
        if let match = findSubview(in: subview, where: predicate) {
            return match
        }
    }

    return nil
}
#endif
