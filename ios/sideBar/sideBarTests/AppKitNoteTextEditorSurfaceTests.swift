#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class AppKitNoteTextEditorSurfaceTests: NotesDetailViewHostingTestCase {
    func testWideMacOSContainerKeepsScrollViewAtHostEdgeAndCentersReadableColumn() async throws {
        let context = await makeNotesDetailViewTestContext(note: makeTestNote(plainText: "Hello"))
        let environment = makeNotesDetailTestEnvironment()
        let hostFrame = NSRect(x: 0, y: 0, width: 900, height: 320)
        let container = AttributedNoteEditorContainer(
            editorViewModel: context.editorViewModel,
            maxContentWidth: 640,
            onEscape: { _ in }
        )
        let controller = mount(container.environmentObject(environment), frame: hostFrame)
        controller.view.layoutSubtreeIfNeeded()
        controller.view.window?.contentView?.layoutSubtreeIfNeeded()
        drainNotesHostingRunLoop()

        let textView = try XCTUnwrap(findDescendantTextView(in: controller.view))
        let scrollView = try XCTUnwrap(textView.enclosingScrollView)
        let expectedHorizontalInset = NoteTextLayout.horizontalPadding + ((hostFrame.width - 640) / 2)

        XCTAssertEqual(scrollView.frame.width, hostFrame.width, accuracy: 0.5)
        XCTAssertEqual(textView.frame.width, hostFrame.width, accuracy: 0.5)
        XCTAssertEqual(textView.textContainerInset.width, expectedHorizontalInset, accuracy: 0.5)
    }

    func testMountedAppKitEditorUsesSharedTypographyAndParagraphMetrics() throws {
        let baseFontSize = NoteTextTypography.defaultBodyFontSize
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(type: .heading, content: [.init(text: "Heading", marks: [])]),
                .init(type: .subheading, content: [.init(text: "Subheading", marks: [])]),
                .paragraph([.init(text: "Body", marks: [])])
            ]
        )
        let textView = try mountEditorTextView(
            document: document,
            baseFontSize: baseFontSize,
            frame: NSRect(x: 0, y: 0, width: 420, height: 280)
        )

        XCTAssertEqual(textView.string, "Title\nHeading\nSubheading\nBody")

        let titleFont = try fontAttribute(in: textView, at: 0)
        let headingFont = try fontAttribute(in: textView, at: 6)
        let subheadingFont = try fontAttribute(in: textView, at: 14)
        let bodyFont = try fontAttribute(in: textView, at: 25)

        XCTAssertEqual(
            titleFont.pointSize,
            NoteTextStyleTypography.platformFont(for: .title, baseFontSize: baseFontSize).pointSize,
            accuracy: 0.001
        )
        XCTAssertEqual(
            headingFont.pointSize,
            NoteTextStyleTypography.platformFont(for: .heading, baseFontSize: baseFontSize).pointSize,
            accuracy: 0.001
        )
        XCTAssertEqual(
            subheadingFont.pointSize,
            NoteTextStyleTypography.platformFont(for: .subheading, baseFontSize: baseFontSize).pointSize,
            accuracy: 0.001
        )
        XCTAssertEqual(
            bodyFont.pointSize,
            NoteTextStyleTypography.platformFont(for: .body, baseFontSize: baseFontSize).pointSize,
            accuracy: 0.001
        )
        XCTAssertTrue(notePlatformFontTraits(from: titleFont).bold)
        XCTAssertTrue(notePlatformFontTraits(from: headingFont).bold)
        XCTAssertTrue(notePlatformFontTraits(from: subheadingFont).bold)
        XCTAssertFalse(notePlatformFontTraits(from: bodyFont).bold)

        try assertParagraphStyle(
            in: textView,
            matches: NoteTextParagraphMetrics.paragraphStyle(for: .title, baseFontSize: baseFontSize),
            at: 0
        )
        try assertParagraphStyle(
            in: textView,
            matches: NoteTextParagraphMetrics.paragraphStyle(for: .heading, baseFontSize: baseFontSize),
            at: 6
        )
        try assertParagraphStyle(
            in: textView,
            matches: NoteTextParagraphMetrics.paragraphStyle(for: .subheading, baseFontSize: baseFontSize),
            at: 14
        )
        try assertParagraphStyle(
            in: textView,
            matches: NoteTextParagraphMetrics.paragraphStyle(for: .paragraph, baseFontSize: baseFontSize),
            at: 25
        )
    }

    func testMountedAppKitEditorUsesInlineCodeBackgroundAndMonospacedFont() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([.init(text: "code", marks: [.inlineCode])])
            ]
        )
        let textView = try mountEditorTextView(
            document: document,
            baseFontSize: NoteTextTypography.defaultBodyFontSize,
            frame: NSRect(x: 0, y: 0, width: 420, height: 180)
        )

        let font = try fontAttribute(in: textView, at: 0)
        let backgroundColor = try backgroundColorAttribute(in: textView, at: 0)

        XCTAssertTrue(notePlatformFontTraits(from: font).monospaced)
        XCTAssertEqual(backgroundColor, NoteTextAppearance.inlineCodeBackgroundColor)
    }

    func testMountedAppKitEditorDoesNotDrawCustomCodeBlockBackground() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .init(type: .codeBlock, content: [.init(text: "abcdefghij\nab", marks: [])])
            ]
        )
        let textView = try mountEditorTextView(
            document: document,
            baseFontSize: NoteTextTypography.defaultBodyFontSize,
            frame: NSRect(x: 0, y: 0, width: 420, height: 180)
        )

        let font = try fontAttribute(in: textView, at: 0)
        XCTAssertNil(textView.textStorage?.attribute(.backgroundColor, at: 0, effectiveRange: nil))

        let longLineRect = try glyphRect(in: textView, characterIndex: 9)
        let shortLineRect = try glyphRect(in: textView, characterIndex: 12)
        let samplePoint = NSPoint(
            x: textView.textContainerInset.width + shortLineRect.maxX + ((longLineRect.maxX - shortLineRect.maxX) * 0.5),
            y: textView.textContainerInset.height + shortLineRect.midY
        )
        let sampledColor = try XCTUnwrap(samplePixelColor(in: textView, at: samplePoint))

        XCTAssertTrue(notePlatformFontTraits(from: font).monospaced)
        assertColorsApproximatelyNotEqual(
            sampledColor,
            NoteTextAppearance.inlineCodeBackgroundColor,
            tolerance: 0.05
        )
    }

    func testMountedAppKitEditorUsesSecondaryLabelCaretTint() throws {
        let textView = try mountEditorTextView(
            document: NotesSemanticDocumentProjection.document(fromPlainText: "Hello"),
            baseFontSize: NoteTextTypography.defaultBodyFontSize,
            frame: NSRect(x: 0, y: 0, width: 420, height: 180)
        )

        XCTAssertEqual(textView.insertionPointColor, .secondaryLabelColor)
    }

    func testReturnKeyCreatesExpectedFollowupBlocksForTitleSubheadingAndBody() throws {
        let titleTextView = try mountEditorTextView(
            document: NotesSemanticDocument(
                version: NotesSemanticDocument.currentVersion,
                blocks: [
                    .init(type: .title, content: [.init(text: "Title", marks: [])])
                ]
            ),
            baseFontSize: NoteTextTypography.defaultBodyFontSize,
            frame: NSRect(x: 0, y: 0, width: 420, height: 180)
        )
        titleTextView.setSelectedRange(NSRange(location: titleTextView.string.utf16.count, length: 0))

        let titleHandled = titleTextView.delegate?.textView?(
            titleTextView,
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        ) ?? false

        XCTAssertTrue(titleHandled)
        XCTAssertEqual(
            mountedEditorSnapshot(from: titleTextView)?.document.blocks.map(\.type),
            [.title, .paragraph]
        )

        let subheadingTextView = try mountEditorTextView(
            document: NotesSemanticDocument(
                version: NotesSemanticDocument.currentVersion,
                blocks: [
                    .init(type: .title, content: [.init(text: "Title", marks: [])]),
                    .init(type: .subheading, content: [.init(text: "Subheading", marks: [])])
                ]
            ),
            baseFontSize: NoteTextTypography.defaultBodyFontSize,
            frame: NSRect(x: 0, y: 0, width: 420, height: 180)
        )
        subheadingTextView.setSelectedRange(NSRange(location: subheadingTextView.string.utf16.count, length: 0))

        let subheadingHandled = subheadingTextView.delegate?.textView?(
            subheadingTextView,
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        ) ?? false

        XCTAssertTrue(subheadingHandled)
        XCTAssertEqual(
            mountedEditorSnapshot(from: subheadingTextView)?.document.blocks.map(\.type),
            [.title, .subheading, .paragraph]
        )

        let bodyTextView = try mountEditorTextView(
            document: NotesSemanticDocument(
                version: NotesSemanticDocument.currentVersion,
                blocks: [
                    .init(type: .title, content: [.init(text: "Title", marks: [])]),
                    .paragraph([.init(text: "Body", marks: [])])
                ]
            ),
            baseFontSize: NoteTextTypography.defaultBodyFontSize,
            frame: NSRect(x: 0, y: 0, width: 420, height: 180)
        )
        bodyTextView.setSelectedRange(NSRange(location: bodyTextView.string.utf16.count, length: 0))

        let bodyHandled = bodyTextView.delegate?.textView?(
            bodyTextView,
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        ) ?? false

        XCTAssertTrue(bodyHandled)
        XCTAssertEqual(
            mountedEditorSnapshot(from: bodyTextView)?.document.blocks.map(\.type),
            [.title, .paragraph, .paragraph]
        )
    }

    func testRangedReturnIsHandledBySharedStructuralMutationLayerOnMacOS() throws {
        let textView = try mountEditorTextView(
            document: NotesSemanticDocument(
                version: NotesSemanticDocument.currentVersion,
                blocks: [
                    .init(type: .title, content: [.init(text: "Title", marks: [])]),
                    .init(type: .heading, content: [.init(text: "Heading", marks: [])])
                ]
            ),
            baseFontSize: NoteTextTypography.defaultBodyFontSize,
            frame: NSRect(x: 0, y: 0, width: 420, height: 180)
        )
        textView.setSelectedRange(NSRange(location: 10, length: 1))

        let handled = textView.delegate?.textView?(
            textView,
            shouldChangeTextIn: textView.selectedRange(),
            replacementString: "\n"
        ) ?? true

        XCTAssertFalse(handled)
        let snapshot = try XCTUnwrap(mountedEditorSnapshot(from: textView))
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .heading, .paragraph])
        XCTAssertEqual(snapshot.document.blocks[1].content, [.init(text: "Head", marks: [])])
        XCTAssertEqual(snapshot.document.blocks[2].content, [.init(text: "ng", marks: [])])
    }

    func testMultilinePasteIsHandledBySharedStructuralMutationLayerOnMacOS() throws {
        let textView = try mountEditorTextView(
            document: NotesSemanticDocument(
                version: NotesSemanticDocument.currentVersion,
                blocks: [
                    .init(type: .title, content: [.init(text: "Title", marks: [])]),
                    .init(type: .heading, content: [.init(text: "Heading", marks: [])])
                ]
            ),
            baseFontSize: NoteTextTypography.defaultBodyFontSize,
            frame: NSRect(x: 0, y: 0, width: 420, height: 180)
        )
        textView.setSelectedRange(NSRange(location: 13, length: 0))

        let handled = textView.delegate?.textView?(
            textView,
            shouldChangeTextIn: textView.selectedRange(),
            replacementString: " Alpha\nBeta"
        ) ?? true

        XCTAssertFalse(handled)
        let snapshot = try XCTUnwrap(mountedEditorSnapshot(from: textView))
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .heading, .paragraph])
        XCTAssertEqual(snapshot.document.blocks[1].content, [.init(text: "Heading Alpha", marks: [])])
        XCTAssertEqual(snapshot.document.blocks[2].content, [.init(text: "Beta", marks: [])])
    }

    func testDoubleReturnExitsCodeBlockIntoParagraphBlockOnMacOS() throws {
        let textView = try mountEditorTextView(
            document: NotesSemanticDocument(
                version: NotesSemanticDocument.currentVersion,
                blocks: [
                    .init(type: .title, content: [.init(text: "Snippet", marks: [])]),
                    .init(type: .codeBlock, content: [.init(text: "let x = 1", marks: [])])
                ]
            ),
            baseFontSize: NoteTextTypography.defaultBodyFontSize,
            frame: NSRect(x: 0, y: 0, width: 420, height: 180)
        )
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))

        XCTAssertTrue(
            textView.delegate?.textView?(
                textView,
                doCommandBy: #selector(NSResponder.insertNewline(_:))
            ) ?? false
        )
        XCTAssertTrue(
            textView.delegate?.textView?(
                textView,
                doCommandBy: #selector(NSResponder.insertNewline(_:))
            ) ?? false
        )

        let snapshot = try XCTUnwrap(mountedEditorSnapshot(from: textView))
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .codeBlock, .paragraph])
        XCTAssertEqual(snapshot.document.blocks[1].content, [.init(text: "let x = 1\n", marks: [])])
        XCTAssertEqual(snapshot.document.blocks[2].content, [.init(text: "", marks: [])])
    }

    func testTypingAttributesStayPlainOnEmptyTrailingParagraphAfterHeadingOnMacOS() throws {
        let textView = try mountEditorTextView(
            document: NotesSemanticDocument(
                version: NotesSemanticDocument.currentVersion,
                blocks: [
                    .init(type: .title, content: [.init(text: "Title", marks: [])]),
                    .init(type: .heading, content: [.init(text: "Heading", marks: [])]),
                    .paragraph([.init(text: "", marks: [])])
                ]
            ),
            baseFontSize: NoteTextTypography.defaultBodyFontSize,
            frame: NSRect(x: 0, y: 0, width: 420, height: 180)
        )
        let font = try XCTUnwrap(textView.typingAttributes[.font] as? NSFont)

        XCTAssertFalse(notePlatformFontTraits(from: font).bold)
    }
}

@MainActor
private func mountedEditorSnapshot(
    from textView: NSTextView
) -> NativeNoteEditorViewModel.PersistenceSnapshot? {
    (textView.delegate as? AppKitNoteTextEditorSurface.Coordinator)?.viewModel.currentPersistenceSnapshot()
}

private func fontAttribute(
    in textView: NSTextView,
    at location: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> NSFont {
    guard textView.string.utf16.count > location else {
        XCTFail("Expected text length > \(location), got \(textView.string.utf16.count)", file: file, line: line)
        throw AppKitNoteTextEditorSurfaceTestError.missingAttribute
    }

    return try XCTUnwrap(
        textView.textStorage?.attribute(.font, at: location, effectiveRange: nil) as? NSFont,
        file: file,
        line: line
    )
}

private func backgroundColorAttribute(
    in textView: NSTextView,
    at location: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> NSColor {
    guard textView.string.utf16.count > location else {
        XCTFail("Expected text length > \(location), got \(textView.string.utf16.count)", file: file, line: line)
        throw AppKitNoteTextEditorSurfaceTestError.missingAttribute
    }

    return try XCTUnwrap(
        textView.textStorage?.attribute(.backgroundColor, at: location, effectiveRange: nil) as? NSColor,
        file: file,
        line: line
    )
}

private func assertParagraphStyle(
    in textView: NSTextView,
    matches expected: NSParagraphStyle,
    at location: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let actual = try XCTUnwrap(
        textView.textStorage?.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle,
        file: file,
        line: line
    )
    XCTAssertEqual(actual.lineSpacing, expected.lineSpacing, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(actual.paragraphSpacingBefore, expected.paragraphSpacingBefore, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(actual.paragraphSpacing, expected.paragraphSpacing, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(actual.headIndent, expected.headIndent, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(actual.firstLineHeadIndent, expected.firstLineHeadIndent, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(actual.tailIndent, expected.tailIndent, accuracy: 0.001, file: file, line: line)
}

private enum AppKitNoteTextEditorSurfaceTestError: Error {
    case missingAttribute
}

@MainActor
private func samplePixelColor(
    in view: NSView,
    at point: NSPoint,
    file: StaticString = #filePath,
    line: UInt = #line
) -> NSColor? {
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
    guard let rep else {
        XCTFail("Expected bitmap image rep", file: file, line: line)
        return nil
    }

    view.cacheDisplay(in: view.bounds, to: rep)
    let pixelX = Int(point.x.rounded(.down))
    let pixelY = Int(point.y.rounded(.down))
    guard pixelX >= 0, pixelX < rep.pixelsWide, pixelY >= 0, pixelY < rep.pixelsHigh else {
        XCTFail("Sample point out of bounds: \(point)", file: file, line: line)
        return nil
    }

    return rep.colorAt(x: pixelX, y: pixelY)
}

@MainActor
private func assertColorsApproximatelyNotEqual(
    _ actual: NSColor,
    _ expected: NSColor,
    tolerance: CGFloat,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let actualColor = actual.usingColorSpace(.deviceRGB)
    let expectedColor = expected.usingColorSpace(.deviceRGB)
    XCTAssertNotNil(actualColor, file: file, line: line)
    XCTAssertNotNil(expectedColor, file: file, line: line)
    guard let actualColor, let expectedColor else { return }

    let redDelta = abs(actualColor.redComponent - expectedColor.redComponent)
    let greenDelta = abs(actualColor.greenComponent - expectedColor.greenComponent)
    let blueDelta = abs(actualColor.blueComponent - expectedColor.blueComponent)
    let alphaDelta = abs(actualColor.alphaComponent - expectedColor.alphaComponent)
    let matchesExpectedWithinTolerance = redDelta <= tolerance &&
        greenDelta <= tolerance &&
        blueDelta <= tolerance &&
        alphaDelta <= tolerance

    XCTAssertFalse(matchesExpectedWithinTolerance, file: file, line: line)
}
#endif
