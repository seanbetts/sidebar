import XCTest
@testable import sideBar
#if os(iOS)
import UIKit

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class NotesMountedEditorSurfaceParityTests: XCTestCase {
    func testMountedReadAndEditorSurfacesLayOutKeyBlocksWithMatchingInsetsAndCharacterRectsOnIOS() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(type: .heading, content: [.init(text: "Heading", marks: [])]),
                .init(type: .subheading, content: [.init(text: "Subheading", marks: [])]),
                .paragraph([.init(text: "Body line", marks: [])])
            ]
        )
        let frame = CGRect(x: 0, y: 0, width: 672, height: 420)
        let readTextView = try makeMountedReadTextView(for: document, frame: frame)
        let editorTextView = try makeMountedEditorTextView(for: document, frame: frame)

        XCTAssertEqual(readTextView.textContainerInset, editorTextView.textContainerInset)

        for characterIndex in [0, 6, 14, 25] {
            let readRect = try characterRect(in: readTextView, characterIndex: characterIndex)
            let editorRect = try characterRect(in: editorTextView, characterIndex: characterIndex)

            XCTAssertEqual(readRect.minX, editorRect.minX, accuracy: 1.0, "characterIndex=\(characterIndex)")
            XCTAssertEqual(readRect.minY, editorRect.minY, accuracy: 1.0, "characterIndex=\(characterIndex)")
            XCTAssertEqual(readRect.height, editorRect.height, accuracy: 1.0, "characterIndex=\(characterIndex)")
        }
    }

    func testMountedReadAndEditorSurfacesPreserveVerticalBlockSpacingForListHeavyNotesOnIOS() throws {
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
                        .init(type: .listItem, content: [.init(text: "Third item", marks: [])])
                    ]
                ),
                .init(type: .heading, content: [.init(text: "Ordered List", marks: [])]),
                .init(
                    type: .orderedList,
                    children: [
                        .init(type: .listItem, content: [.init(text: "First Step", marks: [])]),
                        .init(type: .listItem, content: [.init(text: "Second Step", marks: [])]),
                        .init(type: .listItem, content: [.init(text: "Third Step", marks: [])])
                    ]
                ),
                .init(type: .heading, content: [.init(text: "Task Lists", marks: [])]),
                .init(
                    type: .checklist,
                    children: [
                        .init(type: .listItem, content: [.init(text: "Create note", marks: [])], checked: true),
                        .init(type: .listItem, content: [.init(text: "Review formatting", marks: [])], checked: false)
                    ]
                ),
                .init(type: .heading, content: [.init(text: "Code Blocks", marks: [])]),
                .init(type: .codeBlock, content: [.init(text: "let x = 1", marks: [])])
            ]
        )
        let frame = CGRect(x: 0, y: 0, width: 672, height: 900)
        let readTextView = try makeMountedReadTextView(for: document, frame: frame)
        let editorTextView = try makeMountedEditorTextView(for: document, frame: frame)

        let markers = [
            "Unordered List",
            "First item",
            "Ordered List",
            "First Step",
            "Task Lists",
            "Create note",
            "Code Blocks",
            "let x = 1"
        ]

        for marker in markers {
            let readLocation = try mountedParityLocation(of: marker, in: readTextView.attributedText)
            let editorLocation = try mountedParityLocation(of: marker, in: editorTextView.attributedText)
            let readRect = try characterRect(in: readTextView, characterIndex: readLocation)
            let editorRect = try characterRect(in: editorTextView, characterIndex: editorLocation)

            XCTAssertEqual(readRect.minY, editorRect.minY, accuracy: 1.0, "marker=\(marker)")
        }
    }

    func testMountedReadAndEditorSurfacesMatchWrappedCodeBlockLayoutOnIOS() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([.init(text: "Before", marks: [])]),
                .init(
                    type: .codeBlock,
                    content: [
                        .init(
                            text: "const result = calculateSomethingWithLongArguments(alpha, beta, gamma, delta);",
                            marks: []
                        )
                    ]
                ),
                .paragraph([.init(text: "After", marks: [])])
            ]
        )
        let frame = CGRect(x: 0, y: 0, width: 420, height: 420)
        let readTextView = try makeMountedReadTextView(for: document, frame: frame)
        let editorTextView = try makeMountedEditorTextView(for: document, frame: frame)

        let beforeLocation = try mountedParityLocation(of: "Before", in: readTextView.attributedText)
        let codeLocation = try mountedParityLocation(of: "const result", in: readTextView.attributedText)
        let afterLocation = try mountedParityLocation(of: "After", in: readTextView.attributedText)

        let readBeforeRect = try characterRect(in: readTextView, characterIndex: beforeLocation)
        let readCodeRect = try characterRect(in: readTextView, characterIndex: codeLocation)
        let readAfterRect = try characterRect(in: readTextView, characterIndex: afterLocation)

        let editorBeforeRect = try characterRect(in: editorTextView, characterIndex: beforeLocation)
        let editorCodeRect = try characterRect(in: editorTextView, characterIndex: codeLocation)
        let editorAfterRect = try characterRect(in: editorTextView, characterIndex: afterLocation)

        XCTAssertEqual(readCodeRect.minY, editorCodeRect.minY, accuracy: 1.0)
        XCTAssertEqual(readAfterRect.minY, editorAfterRect.minY, accuracy: 1.0)
        XCTAssertEqual(
            readAfterRect.minY - readBeforeRect.minY,
            editorAfterRect.minY - editorBeforeRect.minY,
            accuracy: 1.0
        )
    }
}

@MainActor
private func makeMountedReadTextView(
    for document: NotesSemanticDocument,
    frame: CGRect
) throws -> UITextView {
    let baseFontSize = NoteTextTypography.defaultBodyFontSize
    return try makeReadTextView(
        document: document,
        frame: frame,
        baseFontSize: baseFontSize,
        maxContentWidth: frame.width
    )
}

@MainActor
private func makeMountedEditorTextView(
    for document: NotesSemanticDocument,
    frame: CGRect
) throws -> UIKitNoteTextEditorSurface.AccessoryTextView {
    let baseFontSize = NoteTextTypography.defaultBodyFontSize
    let canonicalContent = try XCTUnwrap(NotesSemanticDocumentCodec.encode(document))
    let plainText = NotesSemanticDocumentProjection.plainText(from: document)
    let editorViewModel = NativeNoteEditorViewModel()
    editorViewModel.setBaseFontSize(baseFontSize)
    editorViewModel.loadDocument(canonicalContent: canonicalContent, plainText: plainText)
    return try mountTextView(
        viewModel: editorViewModel,
        formattingBarPresentation: .hidden,
        maxContentWidth: frame.width,
        width: frame.width,
        height: frame.height
    )
}

private enum MountedNotesSurfaceParityTestError: Error {
    case missingAttribute
}

private func mountedParityLocation(
    of substring: String,
    in attributedText: NSAttributedString,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> Int {
    let nsString = attributedText.string as NSString
    let range = nsString.range(of: substring)
    guard range.location != NSNotFound else {
        XCTFail("Expected to find substring \(substring)", file: file, line: line)
        throw MountedNotesSurfaceParityTestError.missingAttribute
    }
    return range.location
}
#endif
