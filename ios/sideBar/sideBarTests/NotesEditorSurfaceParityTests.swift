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

    func testReadSurfaceFormattingMatchesEditorSurfaceForSameSemanticNoteOnIOS() throws {
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
        let baseFontSize = NoteTextTypography.defaultBodyFontSize

        let readAttributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: baseFontSize
        )
        let editDocument = try constrainedEditorDocument(
            document: document,
            baseFontSize: baseFontSize
        )

        XCTAssertEqual(readAttributed.string, String(editDocument.characters))
        XCTAssertEqual(readAttributed.string, "Bold Italic Underline")

        try assertMatchingFontTraits(readAttributed, editDocument, at: 0)
        try assertMatchingFontTraits(readAttributed, editDocument, at: 5)
        try assertMatchingUnderline(readAttributed, editDocument, at: 12)
    }

    func testReadSurfaceBoldFontMatchesMountedEditorSurfaceExactlyOnIOS() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([
                    .init(text: "Bold", marks: [.bold])
                ])
            ]
        )
        let baseFontSize = NoteTextTypography.defaultBodyFontSize

        let readAttributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: baseFontSize
        )
        let readFont = try fontAttribute(in: readAttributed, at: 0)
        let expectedFont = notePlatformBoldBodyFont(baseFontSize: baseFontSize)
        let readTraits = notePlatformFontTraits(from: readFont)

        XCTAssertEqual(readFont.fontName, expectedFont.fontName)
        XCTAssertEqual(readFont.pointSize, expectedFont.pointSize, accuracy: 0.001)
        XCTAssertEqual(readTraits.bold, true)
        XCTAssertEqual(readTraits.italic, false)
    }
}

private func assertMatchingFontTraits(
    _ lhs: NSAttributedString,
    _ rhs: AttributedString,
    at location: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let lhsFont = try fontAttribute(in: lhs, at: location, file: file, line: line)
    let lhsTraits = notePlatformFontTraits(from: lhsFont)
    let rhsRange = singleCharacterRange(at: location, in: rhs, file: file, line: line)
    XCTAssertEqual(
        lhsTraits.bold,
        noteRangeHasBoldTrait(rhs, range: rhsRange),
        file: file,
        line: line
    )
    XCTAssertEqual(
        lhsTraits.italic,
        noteRangeHasItalicTrait(rhs, range: rhsRange),
        file: file,
        line: line
    )
}

private func assertMatchingUnderline(
    _ lhs: NSAttributedString,
    _ rhs: AttributedString,
    at location: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let rhsRange = singleCharacterRange(at: location, in: rhs, file: file, line: line)
    XCTAssertEqual(
        try underlineAttribute(in: lhs, at: location, file: file, line: line),
        noteRangeIsUnderlined(rhs, range: rhsRange) ? NSUnderlineStyle.single.rawValue : nil,
        file: file,
        line: line
    )
}

@MainActor
private func constrainedEditorDocument(
    document: NotesSemanticDocument,
    baseFontSize: CGFloat,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> AttributedString {
    var constrained = NotesAttributedDocumentCodec.attributedString(
        from: document,
        baseFontSize: baseFontSize
    )
    NoteTextFormattingDefinition(baseFontSize: baseFontSize).constrainDocument(&constrained)
    _ = (file, line)
    return constrained
}

private func fontAttribute(
    in attributedText: NSAttributedString,
    at location: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> UIFont {
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
    in attributedText: NSAttributedString,
    at location: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> Int? {
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

private func singleCharacterRange(
    at location: Int,
    in text: AttributedString,
    file: StaticString = #filePath,
    line: UInt = #line
) -> Range<AttributedString.Index> {
    guard location >= 0, text.characters.count > location else {
        XCTFail(
            "Expected attributed text length > \(location), got \(text.characters.count)",
            file: file,
            line: line
        )
        return text.startIndex..<text.startIndex
    }

    let lower = text.index(text.startIndex, offsetByCharacters: location)
    let upper = text.index(afterCharacter: lower)
    return lower..<upper
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
    NotesDetailViewTestRetainer.hostingControllers.append(controller)
    NotesDetailViewTestRetainer.hostingWindows.append(window)

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
