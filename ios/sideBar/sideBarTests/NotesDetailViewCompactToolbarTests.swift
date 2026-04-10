import SwiftUI
import XCTest
@testable import sideBar

#if os(iOS)
@MainActor
@available(iOS 26.0, *)
final class NotesDetailViewCompactToolbarTests: NotesDetailViewHostingTestCase {
    func testCompactDirtyStatusDoesNotShiftEditorContentDown() async throws {
        let context = await makeNotesDetailViewTestContext()
        let environment = makeNotesDetailTestEnvironment()

        context.editorViewModel.enterEditMode()

        let controller = mount(
            NavigationStack {
                context.makeView()
                    .environment(\.horizontalSizeClass, .compact)
                    .environmentObject(environment)
            },
            frame: CGRect(x: 0, y: 0, width: 390, height: 844),
            makeKeyAndVisible: true
        )

        let editorTextView = try await waitForCompactToolbarTextView(
            in: controller.view,
            accessibilityIdentifier: "notes-editor-text-view"
        )
        let initialMinY = editorTextView.convert(editorTextView.bounds, to: controller.view).minY

        context.editorViewModel.setDirty(true)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        drainNotesHostingRunLoop()

        let dirtyMinY = try await waitForCompactToolbarTextView(
            in: controller.view,
            accessibilityIdentifier: "notes-editor-text-view"
        )
        .convert(editorTextView.bounds, to: controller.view)
        .minY

        XCTAssertEqual(dirtyMinY, initialMinY, accuracy: 0.5)
    }
}

@MainActor
private func waitForCompactToolbarTextView(
    in rootView: UIView,
    accessibilityIdentifier: String
) async throws -> UITextView {
    var resolvedTextView: UITextView?
    try await waitUntil(timeout: .seconds(2)) {
        resolvedTextView = findCompactToolbarTextView(
            in: rootView,
            accessibilityIdentifier: accessibilityIdentifier
        )
        return resolvedTextView != nil
    }
    return try XCTUnwrap(resolvedTextView)
}

@MainActor
private func findCompactToolbarTextView(
    in view: UIView?,
    accessibilityIdentifier: String
) -> UITextView? {
    guard let view else { return nil }
    if let textView = view as? UITextView, textView.accessibilityIdentifier == accessibilityIdentifier {
        return textView
    }

    for subview in view.subviews {
        if let match = findCompactToolbarTextView(
            in: subview,
            accessibilityIdentifier: accessibilityIdentifier
        ) {
            return match
        }
    }

    return nil
}
#endif
