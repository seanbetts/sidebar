#if os(iOS)
import SwiftUI
import UIKit
import XCTest
@testable import sideBar

@MainActor
final class UIKitNoteFormattingBarTests: NotesDetailViewHostingTestCase {
    func testConfigurationReflectsCanonicalEditorModelIncludingTextStyle() async throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26")
        }

        let note = NotePayload(
            id: "n1",
            name: "Styled",
            document: NotesSemanticDocument(
                version: NotesSemanticDocument.currentVersion,
                blocks: [
                    .init(type: .title, content: [.init(text: "Title", marks: [])]),
                    .init(
                        type: .heading,
                        content: [
                            .init(
                                text: "Styled",
                                marks: [.bold, .italic, .underline, .strikethrough]
                            ),
                            .init(text: " plain", marks: [])
                        ]
                    )
                ]
            ),
            plainText: "Title\nStyled plain",
            path: "/note.md",
            modified: nil,
            created: nil
        )
        let context = await makeAttachedEditingContext(note: note)
        let start = context.nativeViewModel.index(
            forCharacterOffset: 6,
            in: context.nativeViewModel.attributedContent
        )
        let end = context.nativeViewModel.index(
            forCharacterOffset: 12,
            in: context.nativeViewModel.attributedContent
        )
        context.nativeViewModel.selection = AttributedTextSelection(range: start..<end)
        context.nativeViewModel.handleSelectionChange()

        let configuration = context.editorViewModel.noteFormattingBarConfiguration

        XCTAssertTrue(configuration.isEnabled)
        XCTAssertEqual(configuration.activeTextStyle, .heading)
        XCTAssertTrue(configuration.isTextStyleSectionEnabled)
        XCTAssertTrue(configuration.isBoldActive)
        XCTAssertTrue(configuration.isItalicActive)
        XCTAssertTrue(configuration.isUnderlineActive)
        XCTAssertTrue(configuration.isStrikethroughActive)
    }

    func testBarRendersSingleFormattingMenuButton() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26")
        }

        let bar = UIKitNoteFormattingBar(configuration: .disabled)

        XCTAssertEqual(bar.accessibilityIdentifier, "note-formatting-bar")
        XCTAssertEqual(bar.menuButton.accessibilityIdentifier, "note-formatting-menu")
        XCTAssertTrue(bar.menuButton.showsMenuAsPrimaryAction)
        XCTAssertEqual(bar.menuButton.configuration?.image, UIImage(systemName: "textformat"))
    }

    func testMenuContainsTextStyleAndInlineSections() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26")
        }

        let bar = UIKitNoteFormattingBar(
            configuration: .init(
                activeTextStyle: .body,
                isTextStyleSectionEnabled: true,
                isBodyTextStyleEnabled: true,
                isTitleTextStyleEnabled: true,
                isHeadingTextStyleEnabled: true,
                isSubheadingTextStyleEnabled: true,
                isBoldActive: false,
                isItalicActive: false,
                isUnderlineActive: false,
                isStrikethroughActive: false,
                isInlineCodeActive: false,
                isEnabled: true,
                onTextStyleSelection: { _ in },
                onBoldTap: {},
                onItalicTap: {},
                onUnderlineTap: {},
                onStrikethroughTap: {},
                onInlineCodeTap: {}
            )
        )

        let menu = try XCTUnwrap(bar.menuButton.menu)
        XCTAssertEqual(menu.children.compactMap(\.title), ["Text Style", "Inline"])

        let textStyleMenu = try XCTUnwrap(menu.children.first as? UIMenu)
        XCTAssertEqual(
            textStyleMenu.children.compactMap(\.title),
            ["Body", "Title", "Heading", "Subheading"]
        )

        let inlineMenu = try XCTUnwrap(menu.children.last as? UIMenu)
        XCTAssertEqual(
            inlineMenu.children.compactMap(\.title),
            ["Bold", "Italic", "Underline", "Strikethrough", "Inline Code"]
        )
    }

    func testBarRendersDisabledStateWhenEditorIsUnavailable() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26")
        }

        let bar = UIKitNoteFormattingBar(configuration: .disabled)

        XCTAssertFalse(bar.menuButton.isEnabled)
    }

    func testBarReportsCompactIntrinsicSizeForFloatingGlassLayout() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26")
        }

        let bar = UIKitNoteFormattingBar(configuration: .disabled)
        let size = bar.intrinsicContentSize

        XCTAssertNotEqual(size.width, UIView.noIntrinsicMetric)
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertLessThan(size.width, 120)
        XCTAssertEqual(size.height, 48)
    }

    func testBarIntrinsicWidthMatchesCompressedLayoutWidth() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26")
        }

        let bar = UIKitNoteFormattingBar(configuration: .disabled)
        let intrinsicSize = bar.intrinsicContentSize
        let fittedSize = bar.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)

        XCTAssertEqual(fittedSize.width, intrinsicSize.width, accuracy: CGFloat(0.5))
        XCTAssertEqual(fittedSize.height, intrinsicSize.height, accuracy: CGFloat(0.5))
    }

    func testFormattingMenuButtonProvidesMinimumFortyFourPointHitTarget() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26")
        }

        let bar = UIKitNoteFormattingBar(configuration: .disabled)
        bar.frame = CGRect(origin: .zero, size: bar.intrinsicContentSize)
        bar.setNeedsLayout()
        bar.layoutIfNeeded()

        XCTAssertGreaterThanOrEqual(bar.menuButton.frame.width, 44)
        XCTAssertEqual(bar.menuButton.frame.height, CGFloat(44), accuracy: CGFloat(0.5))
        XCTAssertGreaterThan(bar.bounds.height, bar.menuButton.bounds.height)
        XCTAssertLessThanOrEqual(bar.menuButton.frame.maxY, bar.bounds.maxY + CGFloat(0.5))
    }

    func testFormattingMenuButtonUsesCompactInsetsInsideHitTarget() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26")
        }

        let bar = UIKitNoteFormattingBar(configuration: .disabled)
        let configuration = try XCTUnwrap(bar.menuButton.configuration)

        XCTAssertEqual(configuration.contentInsets.top, 4)
        XCTAssertEqual(configuration.contentInsets.bottom, 4)
        XCTAssertEqual(configuration.contentInsets.leading, 6)
        XCTAssertEqual(configuration.contentInsets.trailing, 6)
    }

    func testFormattingMenuButtonInsetGlassBackgroundInsideHitTarget() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26")
        }

        let bar = UIKitNoteFormattingBar(configuration: .disabled)
        let configuration = try XCTUnwrap(bar.menuButton.configuration)
        let backgroundInsets = configuration.background.backgroundInsets

        XCTAssertEqual(backgroundInsets.top, 4)
        XCTAssertEqual(backgroundInsets.bottom, 4)
        XCTAssertEqual(backgroundInsets.leading, 3)
        XCTAssertEqual(backgroundInsets.trailing, 3)
    }

    func testBarAppliesGlassTreatmentAndEnabledStateToMenuButton() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26")
        }

        let bar = UIKitNoteFormattingBar(
            configuration: .init(
                activeTextStyle: .heading,
                isTextStyleSectionEnabled: true,
                isBodyTextStyleEnabled: true,
                isTitleTextStyleEnabled: true,
                isHeadingTextStyleEnabled: true,
                isSubheadingTextStyleEnabled: true,
                isBoldActive: true,
                isItalicActive: false,
                isUnderlineActive: false,
                isStrikethroughActive: false,
                isInlineCodeActive: false,
                isEnabled: true,
                onTextStyleSelection: { _ in },
                onBoldTap: {},
                onItalicTap: {},
                onUnderlineTap: {},
                onStrikethroughTap: {},
                onInlineCodeTap: {}
            )
        )
        let effectView = try XCTUnwrap(findGlassEffectView(in: bar))

        XCTAssertTrue(effectView.effect is UIGlassEffect)
        XCTAssertTrue(bar.menuButton.isEnabled)
        XCTAssertEqual(bar.menuButton.configuration?.cornerStyle, .capsule)
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
