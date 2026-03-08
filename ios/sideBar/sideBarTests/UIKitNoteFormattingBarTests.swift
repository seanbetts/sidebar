import SwiftUI
import UIKit
import XCTest
@testable import sideBar

#if os(iOS)
@MainActor
final class UIKitNoteFormattingBarTests: XCTestCase {
    func testActiveStatesReflectCanonicalEditorModel() async throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26")
        }

        let note = NotePayload(
            id: "n1",
            name: "Styled",
            document: NotesSemanticDocument(
                version: NotesSemanticDocument.currentVersion,
                blocks: [
                    .paragraph([
                        .init(text: "Styled", marks: [.bold, .italic, .underline]),
                        .init(text: " plain", marks: [])
                    ])
                ]
            ),
            plainText: "Styled plain",
            path: "/note.md",
            modified: nil,
            created: nil
        )
        let context = await makeAttachedEditingContext(note: note)
        let styledRange = noteCharacterRange(length: 6, in: context.nativeViewModel.attributedContent)
        context.nativeViewModel.selection = AttributedTextSelection(range: styledRange)
        context.nativeViewModel.handleSelectionChange()

        let configuration = context.editorViewModel.noteFormattingBarConfiguration

        XCTAssertTrue(configuration.isEnabled)
        XCTAssertTrue(configuration.isBoldActive)
        XCTAssertTrue(configuration.isItalicActive)
        XCTAssertTrue(configuration.isUnderlineActive)
    }

    func testButtonTapsRouteThroughSharedFormattingCommandLayer() async throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26")
        }

        let context = await makeAttachedEditingContext(note: makeTestNote(plainText: "Hello"))
        let range = noteCharacterRange(length: 5, in: context.nativeViewModel.attributedContent)
        context.nativeViewModel.selection = AttributedTextSelection(range: range)
        let bar = UIKitNoteFormattingBar(configuration: context.editorViewModel.noteFormattingBarConfiguration)

        bar.button(for: .bold).sendActions(for: .touchUpInside)

        let paragraph = try XCTUnwrap(context.editorViewModel.currentSemanticDocumentSnapshot().blocks.first)
        let segment = try XCTUnwrap(paragraph.content.first)

        XCTAssertTrue(segment.marks.contains(.bold))
        XCTAssertTrue(context.editorViewModel.isDirty)
        XCTAssertTrue(context.nativeViewModel.hasUnsavedChanges)
        XCTAssertNotNil(context.nativeViewModel.autosaveTask)
        XCTAssertTrue(
            noteRangeHasBoldTrait(
                context.nativeViewModel.attributedContent,
                range: noteCharacterRange(length: 5, in: context.nativeViewModel.attributedContent)
            )
        )
        XCTAssertTrue(context.editorViewModel.noteFormattingBarConfiguration.isBoldActive)
    }

    func testBarRendersDisabledStateWhenEditorIsUnavailable() async throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26")
        }

        let context = await makeNotesDetailViewTestContext()
        context.editorViewModel.enterEditMode()
        let configuration = context.editorViewModel.noteFormattingBarConfiguration
        let bar = UIKitNoteFormattingBar(configuration: configuration)

        XCTAssertFalse(configuration.isEnabled)
        XCTAssertFalse(bar.button(for: .bold).isEnabled)
        XCTAssertFalse(bar.button(for: .italic).isEnabled)
        XCTAssertFalse(bar.button(for: .underline).isEnabled)
    }

    func testBarDoesNotComputeFormattingStateFromUIKitOnlyState() async throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26")
        }

        let context = await makeAttachedEditingContext(note: makeTestNote(plainText: "Hello"))
        let bar = UIKitNoteFormattingBar(
            configuration: .init(
                isBoldActive: true,
                isItalicActive: false,
                isUnderlineActive: false,
                isEnabled: true,
                onBoldTap: {},
                onItalicTap: {},
                onUnderlineTap: {}
            )
        )
        let range = noteCharacterRange(length: 5, in: context.nativeViewModel.attributedContent)
        context.nativeViewModel.selection = AttributedTextSelection(range: range)
        context.nativeViewModel.handleSelectionChange()

        XCTAssertTrue(bar.button(for: .bold).isSelected)

        bar.apply(configuration: context.editorViewModel.noteFormattingBarConfiguration)

        XCTAssertFalse(bar.button(for: .bold).isSelected)
        XCTAssertFalse(bar.button(for: .italic).isSelected)
        XCTAssertFalse(bar.button(for: .underline).isSelected)
    }

    func testBarReportsCompactIntrinsicSizeForFloatingGlassLayout() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26")
        }

        let bar = UIKitNoteFormattingBar(configuration: .disabled)
        let size = bar.intrinsicContentSize

        XCTAssertNotEqual(size.width, UIView.noIntrinsicMetric)
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertLessThan(size.width, 240)
        XCTAssertEqual(size.height, 44)
    }

    func testBarIntrinsicWidthMatchesCompressedLayoutWidth() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26")
        }

        let bar = UIKitNoteFormattingBar(configuration: .disabled)
        let intrinsicSize = bar.intrinsicContentSize
        let fittedSize = bar.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)

        XCTAssertEqual(fittedSize.width, intrinsicSize.width, accuracy: 0.5)
        XCTAssertEqual(fittedSize.height, intrinsicSize.height, accuracy: 0.5)
    }

    func testBarPreservesAccessibilityIdentifiersForSharedButtons() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26")
        }

        let bar = UIKitNoteFormattingBar(configuration: .disabled)

        XCTAssertEqual(bar.accessibilityIdentifier, "note-formatting-bar")
        XCTAssertEqual(bar.button(for: .bold).accessibilityIdentifier, "note-formatting-bold")
        XCTAssertEqual(bar.button(for: .italic).accessibilityIdentifier, "note-formatting-italic")
        XCTAssertEqual(bar.button(for: .underline).accessibilityIdentifier, "note-formatting-underline")
    }

    func testBarAppliesGlassTreatmentAndSelectedButtonStyling() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26")
        }

        let bar = UIKitNoteFormattingBar(
            configuration: .init(
                isBoldActive: true,
                isItalicActive: false,
                isUnderlineActive: false,
                isEnabled: true,
                onBoldTap: {},
                onItalicTap: {},
                onUnderlineTap: {}
            )
        )
        let effectView = try XCTUnwrap(findGlassEffectView(in: bar))
        let boldButton = bar.button(for: .bold)
        let italicButton = bar.button(for: .italic)

        XCTAssertTrue(effectView.effect is UIGlassEffect)
        XCTAssertTrue(boldButton.isSelected)
        XCTAssertEqual(boldButton.configuration?.cornerStyle, .capsule)
        XCTAssertEqual(italicButton.configuration?.cornerStyle, .capsule)
        XCTAssertNotEqual(
            boldButton.configuration?.baseForegroundColor?.resolvedColor(with: boldButton.traitCollection),
            italicButton.configuration?.baseForegroundColor?.resolvedColor(with: italicButton.traitCollection)
        )
    }
}

@available(iOS 26.0, *)
private extension UIKitNoteFormattingBarTests {
    func makeAttachedEditingContext(
        note: NotePayload
    ) async -> (editorViewModel: NotesEditorViewModel, nativeViewModel: NativeNoteEditorViewModel) {
        let context = await makeNotesDetailViewTestContext(note: note)
        let nativeViewModel = context.editorViewModel.makeNativeEditorViewModel()
        context.editorViewModel.attachNativeEditor(nativeViewModel)
        context.editorViewModel.enterEditMode()
        return (context.editorViewModel, nativeViewModel)
    }

    func findGlassEffectView(in view: UIView) -> UIVisualEffectView? {
        if let effectView = view as? UIVisualEffectView {
            return effectView
        }

        for subview in view.subviews {
            if let match = findGlassEffectView(in: subview) {
                return match
            }
        }

        return nil
    }
}
#endif
