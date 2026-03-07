import XCTest
import SwiftUI
#if os(iOS)
import UIKit
#endif
@testable import sideBar

#if os(iOS)
@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class NotesEditorSurfaceParityTests: XCTestCase {
    func testMakePlatformTextViewDoesNotAutoAdjustForContentSizeCategory() throws {
        let textView = try mountReadTextView(
            plainText: "One\n\nTwo",
            baseFontSize: 16,
            frame: CGRect(x: 0, y: 0, width: 420, height: 240)
        )

        XCTAssertEqual(textView.adjustsFontForContentSizeCategory, false)
    }

    func testNotesDetailViewReadAndEditBlankLineGapMatchForFormattedParagraphsOnIOS() async throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([.init(text: "Bold", marks: [.bold])]),
                .paragraph([.init(text: "", marks: [])]),
                .paragraph([.init(text: "Italic", marks: [.italic])])
            ]
        )
        let note = NotePayload(
            id: "n1",
            name: "Formatted Gap",
            document: document,
            plainText: "Bold\n\nItalic",
            path: "/note.md",
            modified: nil,
            created: nil
        )
        let context = await makeNotesDetailViewTestContext(note: note)
        let environment = makeNotesDetailTestEnvironment()

        let readController = mount(context.makeView(), environment: environment)
        let readTextView = try XCTUnwrap(findDescendantTextView(in: readController.view))
        let readGap = try lineGap(in: readTextView, fromCharacterAt: 0, toCharacterAt: 6)

        context.editorViewModel.enterEditMode()
        let editController = mount(context.makeView(), environment: environment)
        let editTextView = try XCTUnwrap(findDescendantTextView(in: editController.view))
        let editGap = try lineGap(in: editTextView, fromCharacterAt: 0, toCharacterAt: 6)

        XCTAssertEqual(
            readGap,
            editGap,
            accuracy: 1.0,
            "formatted detail readGap=\(readGap) editGap=\(editGap)"
        )
    }
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
private func lineGap(
    in textView: UITextView,
    fromCharacterAt firstIndex: Int,
    toCharacterAt secondIndex: Int
) throws -> CGFloat {
    let firstRect = try glyphRect(in: textView, characterIndex: firstIndex)
    let secondRect = try glyphRect(in: textView, characterIndex: secondIndex)
    return secondRect.minY - firstRect.maxY
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
private func glyphRect(
    in textView: UITextView,
    characterIndex: Int
) throws -> CGRect {
    let layoutManager = textView.layoutManager
    let textContainer = textView.textContainer
    textContainer.size = CGSize(width: textView.bounds.width, height: CGFloat.greatestFiniteMagnitude)
    layoutManager.ensureLayout(for: textContainer)
    let glyphRange = layoutManager.glyphRange(
        forCharacterRange: NSRange(location: characterIndex, length: 1),
        actualCharacterRange: nil
    )
    return layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
private func mountReadTextView(
    plainText: String,
    baseFontSize: CGFloat,
    frame: CGRect
) throws -> UITextView {
    let document = NotesSemanticDocumentProjection.document(fromPlainText: plainText)
    let controller = UIHostingController(
        rootView: AnyView(
            SelectableNoteReadView(
                document: document,
                maxContentWidth: frame.width,
                onActivateEditing: {}
            )
        )
    )
    _ = baseFontSize
    return try mountHostedTextView(controller: controller, frame: frame)
}

@MainActor
private func mountHostedTextView(
    controller: UIHostingController<AnyView>,
    frame: CGRect
) throws -> UITextView {
    let window = makeHostingWindow(frame: frame)
    window.rootViewController = controller
    window.makeKeyAndVisible()
    controller.view.frame = frame
    controller.view.setNeedsLayout()
    controller.view.layoutIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))

    return try XCTUnwrap(findDescendantTextView(in: controller.view))
}

@MainActor
private func findDescendantTextView(in view: UIView) -> UITextView? {
    if let textView = view as? UITextView {
        return textView
    }

    for subview in view.subviews {
        if let match = findDescendantTextView(in: subview) {
            return match
        }
    }

    return nil
}

@MainActor
private func makeHostingWindow(frame: CGRect) -> UIWindow {
    if let windowScene = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first {
        let window = UIWindow(windowScene: windowScene)
        window.frame = frame
        return window
    }

    return UIWindow(frame: frame)
}
#endif
