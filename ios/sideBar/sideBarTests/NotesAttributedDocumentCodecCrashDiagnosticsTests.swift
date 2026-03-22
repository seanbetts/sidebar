import XCTest
import SwiftUI
@testable import sideBar

@available(iOS 26.0, macOS 26.0, *)
@MainActor
final class NotesCodecCrashTests: XCTestCase {
    func testStandaloneFoundationPresentationIntentAttributeDoesNotCrash() {
        var text = AttributedString("hello")
        let range = text.startIndex..<text.endIndex
        text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] =
            PresentationIntent(.paragraph, identity: 1, parent: nil)

        XCTAssertEqual(String(text.characters), "hello")
    }

    func testStandaloneFoundationCodeBlockIntentDoesNotCrash() {
        var text = AttributedString("let value = 1")
        let range = text.startIndex..<text.endIndex
        text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] =
            PresentationIntent(.codeBlock(languageHint: nil), identity: 1, parent: nil)

        XCTAssertEqual(String(text.characters), "let value = 1")
    }

    func testStandaloneFoundationCodeBlockIntentCanBeReadFromFullRuns() throws {
        var text = AttributedString("let value = 1")
        let range = text.startIndex..<text.endIndex
        text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] =
            PresentationIntent(.codeBlock(languageHint: nil), identity: 1, parent: nil)

        let intent = try XCTUnwrap(
            text.runs.first?.attributes[
                AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self
            ]
        )

        XCTAssertEqual(intent.components.map(\.kind), [.codeBlock(languageHint: nil)])
    }

    func testStandaloneFoundationCodeBlockIntentCanBeReadFromSliceRuns() throws {
        var text = AttributedString("let value = 1")
        let range = text.startIndex..<text.endIndex
        text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] =
            PresentationIntent(.codeBlock(languageHint: nil), identity: 1, parent: nil)

        let intent = try XCTUnwrap(
            diagnosticPresentationIntent(in: text, atCharacterOffset: 0)
        )

        XCTAssertEqual(intent.components.map(\.kind), [.codeBlock(languageHint: nil)])
    }

    func testStandaloneFoundationCodeBlockIntentSurvivesPlainPrefixAppend() throws {
        var prefix = AttributedString("Snippet\n")
        var code = AttributedString("let value = 1")
        let range = code.startIndex..<code.endIndex
        code[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] =
            PresentationIntent(.codeBlock(languageHint: nil), identity: 1, parent: nil)
        prefix.append(code)

        let intent = try XCTUnwrap(
            diagnosticPresentationIntent(in: prefix, atCharacterOffset: 8)
        )

        XCTAssertEqual(intent.components.map(\.kind), [.codeBlock(languageHint: nil)])
    }

    func testStandaloneFoundationCodeBlockIntentSurvivesNoteBoundaryAppend() throws {
        var prefix = AttributedString("Snippet")
        let prefixRange = prefix.startIndex..<prefix.endIndex
        prefix[prefixRange].noteBlock = NotesSemanticDocument.BlockType.title.rawValue

        var boundary = AttributedString("\n")
        let boundaryRange = boundary.startIndex..<boundary.endIndex
        boundary[boundaryRange].noteBlock = NotesSemanticDocument.BlockType.codeBlock.rawValue
        boundary[boundaryRange].noteStructuralBoundary = true

        var code = AttributedString("let value = 1")
        let range = code.startIndex..<code.endIndex
        code[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] =
            PresentationIntent(.codeBlock(languageHint: nil), identity: 1, parent: nil)

        prefix.append(boundary)
        prefix.append(code)

        let intent = try XCTUnwrap(
            diagnosticPresentationIntent(in: prefix, atCharacterOffset: 8)
        )

        XCTAssertEqual(intent.components.map(\.kind), [.codeBlock(languageHint: nil)])
    }

    func testStandaloneFoundationCodeBlockIntentSurvivesStyledNoteBoundaryAppend() throws {
        let baseFontSize: CGFloat = 16

        var prefix = AttributedString("Snippet")
        let prefixRange = prefix.startIndex..<prefix.endIndex
        prefix[prefixRange].font = noteInlineFont(baseFontSize: baseFontSize, bold: false, italic: false)
        #if os(iOS)
        prefix[prefixRange][AttributeScopes.UIKitAttributes.FontAttribute.self] =
            noteEditorPlatformFont(
                baseFontSize: baseFontSize,
                blockType: .title,
                bold: false,
                italic: false
            )
        #elseif os(macOS)
        prefix[prefixRange][AttributeScopes.AppKitAttributes.FontAttribute.self] =
            noteEditorPlatformFont(
                baseFontSize: baseFontSize,
                blockType: .title,
                bold: false,
                italic: false
            )
        #endif
        prefix[prefixRange].paragraphStyle = NoteTextParagraphMetrics.paragraphStyle(
            for: .title,
            baseFontSize: baseFontSize
        )
        prefix[prefixRange].noteBlock = NotesSemanticDocument.BlockType.title.rawValue

        var boundary = AttributedString("\n")
        let boundaryRange = boundary.startIndex..<boundary.endIndex
        boundary[boundaryRange].font = noteInlineFont(baseFontSize: baseFontSize, bold: false, italic: false)
        #if os(iOS)
        boundary[boundaryRange][AttributeScopes.UIKitAttributes.FontAttribute.self] =
            noteEditorPlatformFont(
                baseFontSize: baseFontSize,
                blockType: .codeBlock,
                bold: false,
                italic: false
            )
        #elseif os(macOS)
        boundary[boundaryRange][AttributeScopes.AppKitAttributes.FontAttribute.self] =
            noteEditorPlatformFont(
                baseFontSize: baseFontSize,
                blockType: .codeBlock,
                bold: false,
                italic: false
            )
        #endif
        boundary[boundaryRange].paragraphStyle = NoteTextParagraphMetrics.paragraphStyle(
            for: .codeBlock,
            baseFontSize: baseFontSize
        )
        boundary[boundaryRange].noteBlock = NotesSemanticDocument.BlockType.codeBlock.rawValue
        boundary[boundaryRange].noteStructuralBoundary = true

        var code = AttributedString("let value = 1")
        let range = code.startIndex..<code.endIndex
        code[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] =
            PresentationIntent(.codeBlock(languageHint: nil), identity: 1, parent: nil)

        prefix.append(boundary)
        prefix.append(code)

        let intent = try XCTUnwrap(
            diagnosticPresentationIntent(in: prefix, atCharacterOffset: 8)
        )

        XCTAssertEqual(intent.components.map(\.kind), [.codeBlock(languageHint: nil)])
    }

    func testModuleBridgeCodeBlockIntentDoesNotCrash() {
        let attributed = NotesAttributedDocumentCodec.bridgedFoundationPresentationIntentText(
            "let value = 1",
            presentationIntent: PresentationIntent(
                .codeBlock(languageHint: nil),
                identity: 1,
                parent: nil
            )
        )

        XCTAssertEqual(String(attributed.characters), "let value = 1")
    }

    func testModuleSingleSemanticCodeBlockThroughAttributedBlocksDoesNotCrash() {
        let attributed = NotesAttributedDocumentCodec.debugSingleSemanticCodeBlockAttributedText(
            "let value = 1",
            baseFontSize: 16
        )

        XCTAssertEqual(String(attributed.characters), "let value = 1")
    }

    func testModuleSingleSemanticCodeBlockThroughAttributedBlockDoesNotCrash() {
        let attributed = NotesAttributedDocumentCodec.debugSingleSemanticCodeBlockAttributedBlockText(
            "let value = 1",
            baseFontSize: 16
        )

        XCTAssertEqual(String(attributed.characters), "let value = 1")
    }

    func testModuleCopiedBridgeCodeBlockIntentDoesNotCrash() {
        let attributed = NotesAttributedDocumentCodec.debugCopiedBridgedPresentationIntentText(
            "let value = 1",
            presentationIntent: PresentationIntent(
                .codeBlock(languageHint: nil),
                identity: 1,
                parent: nil
            )
        )

        XCTAssertEqual(String(attributed.characters), "let value = 1")
    }

    func testModuleIdentitySourceBridgeCodeBlockIntentDoesNotCrash() {
        let attributed = NotesAttributedDocumentCodec.debugIdentitySourceBridgeCodeBlockText(
            "let value = 1"
        )

        XCTAssertEqual(String(attributed.characters), "let value = 1")
    }

    func testModuleLocalBlockBridgeCodeBlockIntentDoesNotCrash() {
        let attributed = NotesAttributedDocumentCodec.debugLocalBlockBridgeCodeBlockText(
            "let value = 1"
        )

        XCTAssertEqual(String(attributed.characters), "let value = 1")
    }

    func testModuleSwitchedLocalBlockBridgeCodeBlockIntentDoesNotCrash() {
        let attributed = NotesAttributedDocumentCodec.debugSwitchedLocalBlockBridgeCodeBlockText(
            "let value = 1"
        )

        XCTAssertEqual(String(attributed.characters), "let value = 1")
    }

    func testModuleCodecComposedTitleThenCodeBlockTextCanBeInspected() throws {
        let attributed = NotesAttributedDocumentCodec.debugCodecComposedTitleThenCodeBlockText(
            baseFontSize: 16
        )

        let intent = try XCTUnwrap(
            diagnosticPresentationIntent(in: attributed, atCharacterOffset: 8)
        )

        XCTAssertEqual(intent.components.map(\.kind), [.codeBlock(languageHint: nil)])
    }

    func testModuleWrapperStyleTitleThenCodeBlockTextCanBeInspected() throws {
        let attributed = NotesAttributedDocumentCodec.debugWrapperStyleTitleThenCodeBlockText(
            baseFontSize: 16
        )

        let intent = try XCTUnwrap(
            diagnosticPresentationIntent(in: attributed, atCharacterOffset: 8)
        )

        XCTAssertEqual(intent.components.map(\.kind), [.codeBlock(languageHint: nil)])
    }

    func testModuleBlockArrayTitleThenCodeBlockTextCanBeInspected() throws {
        let attributed = NotesAttributedDocumentCodec.debugBlockArrayTitleThenCodeBlockText(
            baseFontSize: 16
        )

        let intent = try XCTUnwrap(
            diagnosticPresentationIntent(in: attributed, atCharacterOffset: 8)
        )

        XCTAssertEqual(intent.components.map(\.kind), [.codeBlock(languageHint: nil)])
    }

    func testStandaloneFoundationNestedListIntentDoesNotCrash() {
        var text = AttributedString("item")
        let range = text.startIndex..<text.endIndex
        let container = PresentationIntent(.orderedList, identity: 1, parent: nil)
        let item = PresentationIntent(.listItem(ordinal: 1), identity: 2, parent: container)
        text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] =
            PresentationIntent(.paragraph, identity: 3, parent: item)

        XCTAssertEqual(String(text.characters), "item")
    }
}

@available(iOS 26.0, macOS 26.0, *)
private func diagnosticPresentationIntent(
    in text: AttributedString,
    atCharacterOffset offset: Int
) -> PresentationIntent? {
    guard offset >= 0, offset < text.characters.count else { return nil }
    let lower = text.index(text.startIndex, offsetByCharacters: offset)
    let upper = text.index(afterCharacter: lower)
    return text[lower..<upper].runs.first?.attributes[
        AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self
    ]
}
