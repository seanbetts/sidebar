#if os(iOS)
import UIKit
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, *)
final class NotesHeldReadSurfaceViewportTests: NotesDetailViewHostingTestCase {
    func testReadToEditActivationFromMiddleKeepsHeldReadSurfaceTargetLineAtSameRelativePosition() async throws {
        let plainText = (0..<120)
            .map { index in "Line \(index) body text" }
            .joined(separator: "\n")
        let context = await makeNotesDetailViewTestContext(note: makeTestNote(plainText: plainText))
        let environment = makeNotesDetailTestEnvironment()
        let controller = mount(context.makeView(), environment: environment, makeKeyAndVisible: true)
        let readTextView = try XCTUnwrap(findTextView(in: controller.view))
        let targetOffset = NSString(string: plainText).range(of: "Line 70 body text").location

        let readTargetPosition = try XCTUnwrap(
            readTextView.position(from: readTextView.beginningOfDocument, offset: targetOffset)
        )
        let initialReadTargetRect = readTextView.caretRect(for: readTargetPosition)
        let readViewportHeight = readTextView.bounds.inset(by: readTextView.adjustedContentInset).height
        let targetReadOffset = max(
            initialReadTargetRect.midY - (readViewportHeight * 0.55),
            -readTextView.adjustedContentInset.top
        )
        readTextView.setContentOffset(CGPoint(x: 0, y: targetReadOffset), animated: false)
        drainNotesHostingRunLoop()
        let readTargetRect = readTextView.caretRect(for: readTargetPosition)
        let readViewport = readTextView.bounds.inset(by: readTextView.adjustedContentInset)
        let expectedViewportAnchorY = readTargetRect.midY - readViewport.minY

        context.editorViewModel.enterEditMode(
            at: .characterOffset(targetOffset),
            viewportAnchorY: expectedViewportAnchorY
        )

        await waitUntil {
            context.editorViewModel.isHoldingReadSurfaceDuringEditEntry &&
                findTextView(
                    in: controller.view,
                    accessibilityIdentifier: "notes-read-text-view"
                ) != nil
        }

        let heldReadTextView = try XCTUnwrap(
            findTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-read-text-view"
            )
        )
        let heldTargetPosition = try XCTUnwrap(
            heldReadTextView.position(from: heldReadTextView.beginningOfDocument, offset: targetOffset)
        )
        let heldTargetRect = heldReadTextView.caretRect(for: heldTargetPosition)
        let heldViewport = heldReadTextView.bounds.inset(by: heldReadTextView.adjustedContentInset)
        let actualViewportAnchorY = heldTargetRect.midY - heldViewport.minY

        XCTAssertEqual(heldReadTextView.contentOffset.y, targetReadOffset, accuracy: 1)
        XCTAssertEqual(
            actualViewportAnchorY,
            expectedViewportAnchorY,
            accuracy: 2,
            "heldTargetRect=\(heldTargetRect) heldViewport=\(heldViewport) "
                + "heldContentOffset=\(heldReadTextView.contentOffset) "
                + "expectedViewportAnchorY=\(expectedViewportAnchorY)"
        )
    }
}

@MainActor
private func findTextView(in view: UIView?, accessibilityIdentifier: String) -> UITextView? {
    guard let view else { return nil }
    if let textView = view as? UITextView, textView.accessibilityIdentifier == accessibilityIdentifier {
        return textView
    }
    for subview in view.subviews {
        if let match = findTextView(in: subview, accessibilityIdentifier: accessibilityIdentifier) {
            return match
        }
    }
    return nil
}
#endif
