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
        XCTAssertFalse(bar.menuButton.showsMenuAsPrimaryAction)
        XCTAssertNil(bar.menuButton.menu)
        XCTAssertEqual(bar.menuButton.configuration?.image, UIImage(systemName: "textformat"))
    }

    func testNoteTextStyleUsesShortSubheadLabel() {
        XCTAssertEqual(NoteTextStyle.subheading.displayName, "Subhead")
    }

    func testPopoverContainsTextStyleStripAndGroupedActionRows() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26")
        }

        let popoverView = UIKitNoteFormattingPopoverView(
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
        popoverView.frame = CGRect(x: 0, y: 0, width: 360, height: 220)
        popoverView.setNeedsLayout()
        popoverView.layoutIfNeeded()

        XCTAssertNotNil(
            findDescendantView(in: popoverView, accessibilityIdentifier: "note-formatting-popover")
        )
        XCTAssertNotNil(
            findDescendantView(in: popoverView, accessibilityIdentifier: "note-formatting-text-style-strip")
        )
        XCTAssertNotNil(
            findDescendantView(in: popoverView, accessibilityIdentifier: "note-formatting-inline-group")
        )
        XCTAssertNotNil(
            findDescendantView(in: popoverView, accessibilityIdentifier: "note-formatting-inline-code-group")
        )
        XCTAssertNotNil(
            findDescendantView(in: popoverView, accessibilityIdentifier: "note-formatting-link-group")
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

    func testFormattingMenuButtonDoesNotDrawNestedBackgroundInsideContainer() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26")
        }

        let bar = UIKitNoteFormattingBar(configuration: .disabled)
        let configuration = try XCTUnwrap(bar.menuButton.configuration)
        let background = configuration.background

        XCTAssertNil(background.visualEffect)
        XCTAssertEqual(background.strokeWidth, 0)
        if let strokeColor = background.strokeColor {
            XCTAssertEqual(strokeColor.cgColor.alpha, 0, accuracy: CGFloat(0.001))
        }
        XCTAssertEqual(background.backgroundInsets.top, 0)
        XCTAssertEqual(background.backgroundInsets.bottom, 0)
        XCTAssertEqual(background.backgroundInsets.leading, 0)
        XCTAssertEqual(background.backgroundInsets.trailing, 0)
    }

    func testBarUsesOnlyOuterGlassTreatmentAndLeavesMenuButtonPlain() throws {
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
        let buttonConfiguration = try XCTUnwrap(bar.menuButton.configuration)

        XCTAssertTrue(effectView.effect is UIGlassEffect)
        XCTAssertTrue(bar.menuButton.isEnabled)
        XCTAssertNil(buttonConfiguration.background.visualEffect)
        XCTAssertEqual(buttonConfiguration.background.strokeWidth, 0)
    }

    func testPopoverLayoutPrefersBelowForFloatingPresentationWhenSpaceAllows() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26")
        }

        let layout = UIKitNoteFormattingBar.resolvePopoverLayout(
            anchorFrame: CGRect(x: 320, y: 60, width: 44, height: 44),
            containerBounds: CGRect(x: 0, y: 0, width: 400, height: 900),
            safeAreaInsets: UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
            popoverSize: CGSize(width: 280, height: 220),
            presentation: .floatingTopTrailing
        )

        XCTAssertEqual(layout.direction, .below)
        XCTAssertEqual(layout.frame.minY, 114, accuracy: 0.5)
    }

    func testPopoverLayoutPrefersAboveForKeyboardAccessoryWhenSpaceAllows() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26")
        }

        let layout = UIKitNoteFormattingBar.resolvePopoverLayout(
            anchorFrame: CGRect(x: 320, y: 760, width: 44, height: 44),
            containerBounds: CGRect(x: 0, y: 0, width: 400, height: 900),
            safeAreaInsets: UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
            popoverSize: CGSize(width: 280, height: 220),
            presentation: .keyboardAccessory
        )

        XCTAssertEqual(layout.direction, .above)
        XCTAssertEqual(layout.frame.minY, 530, accuracy: 0.5)
    }

    func testPopoverLayoutFlipsBelowWhenAccessoryPresentationHasInsufficientSpaceAbove() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26")
        }

        let layout = UIKitNoteFormattingBar.resolvePopoverLayout(
            anchorFrame: CGRect(x: 320, y: 120, width: 44, height: 44),
            containerBounds: CGRect(x: 0, y: 0, width: 400, height: 900),
            safeAreaInsets: UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
            popoverSize: CGSize(width: 280, height: 220),
            presentation: .keyboardAccessory
        )

        XCTAssertEqual(layout.direction, .below)
        XCTAssertEqual(layout.frame.minY, 174, accuracy: 0.5)
    }

    func testPopoverLayoutClampsHorizontallyWithinSafeArea() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26")
        }

        let layout = UIKitNoteFormattingBar.resolvePopoverLayout(
            anchorFrame: CGRect(x: 20, y: 60, width: 44, height: 44),
            containerBounds: CGRect(x: 0, y: 0, width: 400, height: 900),
            safeAreaInsets: UIEdgeInsets(top: 0, left: 24, bottom: 0, right: 24),
            popoverSize: CGSize(width: 280, height: 220),
            presentation: .floatingTopTrailing
        )

        XCTAssertEqual(layout.frame.minX, 32, accuracy: 0.5)
        XCTAssertEqual(layout.frame.maxX, 312, accuracy: 0.5)
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

    func findDescendantView(in view: UIView, accessibilityIdentifier: String) -> UIView? {
        if view.accessibilityIdentifier == accessibilityIdentifier {
            return view
        }

        for subview in view.subviews {
            if let match = findDescendantView(in: subview, accessibilityIdentifier: accessibilityIdentifier) {
                return match
            }
        }

        return nil
    }
}
#endif
