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

    func testReadSurfaceFormattingMatchesEditorSurfaceForSameSemanticNoteOnIOS() async throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([
                    .init(text: "Bold", marks: [.bold]),
                    .init(text: " ", marks: []),
                    .init(text: "Italic", marks: [.italic]),
                    .init(text: " ", marks: []),
                    .init(text: "Underline", marks: [.underline])
                ])
            ]
        )
        let note = NotePayload(
            id: "n1",
            name: "Formatting Parity",
            document: document,
            plainText: "Bold Italic Underline",
            path: "/note.md",
            modified: nil,
            created: nil
        )
        let context = await makeNotesDetailViewTestContext(note: note)
        let environment = makeNotesDetailTestEnvironment()

        let readController = mount(context.makeView(), environment: environment)
        let readTextView = try XCTUnwrap(findDescendantTextView(in: readController.view))
        let readAttributed = try attributedText(
            in: readTextView,
            expectedString: "Bold Italic Underline"
        )

        context.editorViewModel.enterEditMode()
        let editController = mount(context.makeView(), environment: environment)
        let editTextView = try XCTUnwrap(findDescendantTextView(in: editController.view))
        let editAttributed = try attributedText(
            in: editTextView,
            expectedString: "Bold Italic Underline"
        )

        XCTAssertEqual(readAttributed.string, editAttributed.string)
        XCTAssertEqual(readAttributed.string, "Bold Italic Underline")

        assertMatchingFontTraits(readTextView, editTextView, at: 0)
        assertMatchingFontTraits(readTextView, editTextView, at: 5)
        assertMatchingUnderline(readTextView, editTextView, at: 12)
    }

    func testReadSurfaceBoldFontMatchesMountedEditorSurfaceExactlyOnIOS() async throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([
                    .init(text: "Bold", marks: [.bold])
                ])
            ]
        )
        let note = NotePayload(
            id: "n1",
            name: "Bold Parity",
            document: document,
            plainText: "Bold",
            path: "/note.md",
            modified: nil,
            created: nil
        )
        let context = await makeNotesDetailViewTestContext(note: note)
        let environment = makeNotesDetailTestEnvironment()

        let readController = mount(context.makeView(), environment: environment)
        let readTextView = try XCTUnwrap(findDescendantTextView(in: readController.view))
        _ = try attributedText(in: readTextView, expectedString: "Bold")
        let readFont = try fontAttribute(in: readTextView, at: 0)

        context.editorViewModel.enterEditMode()
        let editController = mount(context.makeView(), environment: environment)
        let editTextView = try XCTUnwrap(findDescendantTextView(in: editController.view))
        _ = try attributedText(in: editTextView, expectedString: "Bold")
        let editFont = try fontAttribute(in: editTextView, at: 0)

        XCTAssertEqual(readFont.fontName, editFont.fontName)
        XCTAssertEqual(readFont.pointSize, editFont.pointSize, accuracy: 0.001)
    }
}

private func assertMatchingFontTraits(
    _ lhs: UITextView,
    _ rhs: UITextView,
    at location: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    do {
        let lhsFont = try fontAttribute(in: lhs, at: location, file: file, line: line)
        let rhsFont = try fontAttribute(in: rhs, at: location, file: file, line: line)
        XCTAssertEqual(
            notePlatformFontTraits(from: lhsFont),
            notePlatformFontTraits(from: rhsFont),
            file: file,
            line: line
        )
    } catch {
        return
    }
}

private func assertMatchingUnderline(
    _ lhs: UITextView,
    _ rhs: UITextView,
    at location: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    do {
        XCTAssertEqual(
            try underlineAttribute(in: lhs, at: location, file: file, line: line),
            try underlineAttribute(in: rhs, at: location, file: file, line: line),
            file: file,
            line: line
        )
    } catch {
        return
    }
}

private func attributedText(
    in textView: UITextView,
    expectedString: String,
    timeout: TimeInterval = 0.5,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> NSAttributedString {
    let deadline = Date().addingTimeInterval(timeout)

    while Date() <= deadline {
        let attributedText = textView.attributedText ?? NSAttributedString()
        if attributedText.string == expectedString {
            return attributedText
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }

    XCTFail(
        "Expected mounted text view content '\(expectedString)', got '\(textView.attributedText.string)'",
        file: file,
        line: line
    )
    throw NotesEditorSurfaceParityTestError.missingAttribute
}

private func fontAttribute(
    in textView: UITextView,
    at location: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> UIFont {
    let attributedText = textView.attributedText ?? NSAttributedString()
    guard attributedText.length > location else {
        XCTFail(
            "Expected attributed text length > \(location), got \(attributedText.length)",
            file: file,
            line: line
        )
        throw NotesEditorSurfaceParityTestError.missingAttribute
    }

    return try XCTUnwrap(
        attributedText.attribute(.font, at: location, effectiveRange: nil) as? UIFont,
        file: file,
        line: line
    )
}

private func underlineAttribute(
    in textView: UITextView,
    at location: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> Int? {
    let attributedText = textView.attributedText ?? NSAttributedString()
    guard attributedText.length > location else {
        XCTFail(
            "Expected attributed text length > \(location), got \(attributedText.length)",
            file: file,
            line: line
        )
        throw NotesEditorSurfaceParityTestError.missingAttribute
    }

    return attributedText.attribute(.underlineStyle, at: location, effectiveRange: nil) as? Int
}

private enum NotesEditorSurfaceParityTestError: Error {
    case missingAttribute
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
