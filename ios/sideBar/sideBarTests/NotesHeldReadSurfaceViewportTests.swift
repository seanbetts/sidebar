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

    func testReadToEditActivationPreservesViewportOffsetForListAndCodeHeavyNotes() async throws {
        let note = makeComplexViewportParityNote()
        let plainText = note.plainText
        let context = await makeNotesDetailViewTestContext(note: note)
        let environment = makeNotesDetailTestEnvironment()
        let controller = mount(context.makeView(), environment: environment, makeKeyAndVisible: true)
        let readTextView = try XCTUnwrap(findTextView(in: controller.view))
        let targetOffset = NSString(string: plainText).range(of: "Code Blocks").location

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
        drainNotesHostingRunLoop()
        drainNotesHostingRunLoop()

        let editorTextView = try XCTUnwrap(
            findTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-editor-text-view"
            ) as? UIKitNoteTextEditorSurface.AccessoryTextView
        )

        XCTAssertEqual(
            editorTextView.contentOffset.y,
            targetReadOffset,
            accuracy: 1,
            "readOffset=\(targetReadOffset) editorOffset=\(editorTextView.contentOffset.y) "
                + "expectedViewportAnchorY=\(expectedViewportAnchorY)"
        )
    }
}

@MainActor
@available(iOS 26.0, *)
private func makeComplexViewportParityNote() -> NotePayload {
    let document = NotesSemanticDocument(
        version: NotesSemanticDocument.currentVersion,
        blocks: [
            .init(type: .title, content: [.init(text: "Test Note", marks: [])]),
            .init(type: .heading, content: [.init(text: "Unordered List", marks: [])]),
            .init(
                type: .unorderedList,
                children: [
                    .init(type: .listItem, content: [.init(text: "First item", marks: [])]),
                    .init(type: .listItem, content: [.init(text: "Second item", marks: [])]),
                    .init(type: .listItem, content: [.init(text: "Third item", marks: [])]),
                    .init(type: .listItem, content: [.init(text: "Fourth item", marks: [])]),
                    .init(type: .listItem, content: [.init(text: "Fifth item", marks: [])])
                ]
            ),
            .init(type: .heading, content: [.init(text: "Ordered List", marks: [])]),
            .init(
                type: .orderedList,
                children: [
                    .init(type: .listItem, content: [.init(text: "First Step", marks: [])]),
                    .init(type: .listItem, content: [.init(text: "Second Step", marks: [])]),
                    .init(type: .listItem, content: [.init(text: "Third Step", marks: [])]),
                    .init(type: .listItem, content: [.init(text: "Fourth Step", marks: [])])
                ]
            ),
            .paragraph([.init(text: "---", marks: [])]),
            .init(type: .heading, content: [.init(text: "Task Lists", marks: [])]),
            .init(type: .subheading, content: [.init(text: "Simple Tasks", marks: [])]),
            .init(
                type: .checklist,
                children: [
                    .init(type: .listItem, content: [.init(text: "Create note", marks: [])], checked: true),
                    .init(
                        type: .listItem,
                        content: [.init(text: "Add markdown content", marks: [])],
                        checked: true
                    ),
                    .init(type: .listItem, content: [.init(text: "Review formatting", marks: [])], checked: false),
                    .init(type: .listItem, content: [.init(text: "Add more examples", marks: [])], checked: false)
                ]
            ),
            .init(type: .subheading, content: [.init(text: "Nested Tasks", marks: [])]),
            .init(
                type: .checklist,
                children: [
                    .init(type: .listItem, content: [.init(text: "Complete Phase 1", marks: [])], checked: true),
                    .init(type: .listItem, content: [.init(text: "Start Phase 2", marks: [])], checked: true)
                ]
            ),
            .paragraph([.init(text: "---", marks: [])]),
            .init(type: .heading, content: [.init(text: "Code Blocks", marks: [])]),
            .init(type: .subheading, content: [.init(text: "JavaScript", marks: [])]),
            .init(
                type: .codeBlock,
                content: [.init(text: "function greet(name) {\nconsole.log('Hello, ${name}!');\nreturn true;\n}", marks: [])]
            ),
            .init(type: .subheading, content: [.init(text: "Python", marks: [])]),
            .init(
                type: .codeBlock,
                content: [
                    .init(
                        text: "def calculate_sum(a, b):\n    return a + b\nresult = calculate_sum(5, 10)\nprint(f\"Result: {result}\")",
                        marks: []
                    )
                ]
            ),
            .paragraph([.init(text: "---", marks: [])])
        ]
    )

    return NotePayload(
        id: "complex-parity-note",
        name: "Test Note",
        document: document,
        plainText: NotesSemanticDocumentProjection.plainText(from: document),
        path: "/complex-parity-note.md",
        modified: nil,
        created: nil
    )
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
