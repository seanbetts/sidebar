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

    func testNoteTextStyleAllCasesFollowVisualPickerOrder() {
        XCTAssertEqual(NoteTextStyle.allCases, [.title, .heading, .subheading, .body])
    }

    func testPopoverContainsTextStyleStripAndGroupedActionRows() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26")
        }
        let popoverView = makePopoverView(activeTextStyle: .body)
        popoverView.frame = CGRect(x: 0, y: 0, width: 360, height: 220)
        popoverView.setNeedsLayout()
        popoverView.layoutIfNeeded()

        let inlineRow: UIStackView = try XCTUnwrap(
            findDescendant(in: popoverView, accessibilityIdentifier: "note-formatting-inline-actions-row")
        )
        let bottomRow: UIStackView = try XCTUnwrap(
            findDescendant(in: popoverView, accessibilityIdentifier: "note-formatting-bottom-actions-row")
        )

        XCTAssertNotNil(findDescendant(in: popoverView, accessibilityIdentifier: "note-formatting-popover") as UIView?)
        XCTAssertNotNil(findDescendant(in: popoverView, accessibilityIdentifier: "note-formatting-text-style-strip") as UIView?)
        XCTAssertEqual(
            inlineRow.arrangedSubviews.compactMap(\.accessibilityIdentifier),
            ["note-formatting-inline-group", "note-formatting-code-group"]
        )
        XCTAssertEqual(
            bottomRow.arrangedSubviews.compactMap(\.accessibilityIdentifier),
            [
                "note-formatting-link-group",
                "note-formatting-future-list-group",
                "note-formatting-future-blockquote-group"
            ]
        )
    }

    func testPopoverUsesGlassShellAndGlassGroupedControls() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26")
        }
        let popoverView = makePopoverView(activeTextStyle: .heading)
        popoverView.frame = CGRect(x: 0, y: 0, width: 360, height: 220)
        popoverView.setNeedsLayout()
        popoverView.layoutIfNeeded()

        let shell: UIVisualEffectView = try XCTUnwrap(
            findDescendant(in: popoverView, accessibilityIdentifier: "note-formatting-popover-glass")
        )
        let inlineGroup: UIVisualEffectView = try XCTUnwrap(
            findDescendant(in: popoverView, accessibilityIdentifier: "note-formatting-inline-group")
        )
        let codeGroup: UIVisualEffectView = try XCTUnwrap(
            findDescendant(in: popoverView, accessibilityIdentifier: "note-formatting-code-group")
        )
        let linkGroup: UIVisualEffectView = try XCTUnwrap(
            findDescendant(in: popoverView, accessibilityIdentifier: "note-formatting-link-group")
        )

        XCTAssertTrue(shell.effect is UIGlassEffect)
        XCTAssertTrue(inlineGroup.effect is UIGlassEffect)
        XCTAssertTrue(codeGroup.effect is UIGlassEffect)
        XCTAssertTrue(linkGroup.effect is UIGlassEffect)
    }

    func testPopoverTextStylesUseCanonicalOrderAndTypographyTokens() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26")
        }
        let popoverView = makePopoverView(activeTextStyle: .title)
        popoverView.frame = CGRect(x: 0, y: 0, width: 360, height: 220)
        popoverView.setNeedsLayout()
        popoverView.layoutIfNeeded()

        let strip: UIStackView = try XCTUnwrap(
            findDescendant(in: popoverView, accessibilityIdentifier: "note-formatting-text-style-buttons")
        )
        let orderedIdentifiers = strip.arrangedSubviews.compactMap(\.accessibilityIdentifier)
        XCTAssertEqual(strip.spacing, 4, accuracy: CGFloat(0.01))
        XCTAssertEqual(
            orderedIdentifiers,
            [
                "note-formatting-text-style-title",
                "note-formatting-text-style-heading",
                "note-formatting-text-style-subheading",
                "note-formatting-text-style-body"
            ]
        )

        let titleButton: UIButton = try XCTUnwrap(
            findDescendant(in: popoverView, accessibilityIdentifier: "note-formatting-text-style-title")
        )
        let bodyButton: UIButton = try XCTUnwrap(
            findDescendant(in: popoverView, accessibilityIdentifier: "note-formatting-text-style-body")
        )
        let titleFont = try XCTUnwrap(titleButton.titleLabel?.font)
        let bodyFont = try XCTUnwrap(bodyButton.titleLabel?.font)
        XCTAssertEqual(
            titleFont.pointSize,
            NoteTextStyleTypography.platformFont(
                for: .title,
                baseFontSize: NoteTextTypography.defaultBodyFontSize
            ).pointSize,
            accuracy: CGFloat(0.01)
        )
        XCTAssertEqual(
            bodyFont.pointSize,
            NoteTextStyleTypography.platformFont(
                for: .body,
                baseFontSize: NoteTextTypography.defaultBodyFontSize
            ).pointSize,
            accuracy: CGFloat(0.01)
        )
        XCTAssertGreaterThan(titleFont.pointSize, bodyFont.pointSize)
        XCTAssertEqual(titleButton.configuration?.contentInsets.leading, 8)
        XCTAssertEqual(titleButton.configuration?.contentInsets.trailing, 8)
        XCTAssertEqual(bodyButton.configuration?.contentInsets.leading, 8)
        XCTAssertEqual(bodyButton.configuration?.contentInsets.trailing, 8)
        XCTAssertEqual(titleButton.configuration?.background.backgroundInsets.leading, 0)
        XCTAssertEqual(titleButton.configuration?.background.backgroundInsets.trailing, 0)
        XCTAssertEqual(titleButton.configuration?.attributedTitle?.characters.map(String.init).joined(), "Title")
        XCTAssertEqual(bodyButton.configuration?.attributedTitle?.characters.map(String.init).joined(), "Body")
        XCTAssertEqual(strip.frame.minX, 0, accuracy: CGFloat(0.5))
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
        let effectView: UIVisualEffectView = try XCTUnwrap(findDescendant(in: bar, accessibilityIdentifier: nil))
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

    func testTapOutsidePopoverDismissesIt() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26")
        }

        let hostView = UIView(frame: CGRect(x: 0, y: 0, width: 500, height: 900))
        let bar = UIKitNoteFormattingBar(configuration: makeEnabledConfiguration())
        bar.frame = CGRect(x: 420, y: 760, width: 60, height: 48)
        hostView.addSubview(bar)
        bar.setNeedsLayout()
        bar.layoutIfNeeded()

        bar.presentPopover()
        let popover = try XCTUnwrap(bar.popoverView)
        XCTAssertFalse(popover.isHidden)

        bar.dismissPopoverIfNeeded(forTapLocation: CGPoint(x: 24, y: 24), in: hostView)

        XCTAssertTrue(popover.isHidden)
    }

    func testTapInsidePopoverDoesNotDismissIt() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26")
        }

        let hostView = UIView(frame: CGRect(x: 0, y: 0, width: 500, height: 900))
        let bar = UIKitNoteFormattingBar(configuration: makeEnabledConfiguration())
        bar.frame = CGRect(x: 420, y: 760, width: 60, height: 48)
        hostView.addSubview(bar)
        bar.setNeedsLayout()
        bar.layoutIfNeeded()

        bar.presentPopover()
        let popover = try XCTUnwrap(bar.popoverView)
        XCTAssertFalse(popover.isHidden)

        let insidePoint = bar.convert(CGPoint(x: popover.frame.midX, y: popover.frame.midY), to: hostView)
        bar.dismissPopoverIfNeeded(forTapLocation: insidePoint, in: hostView)

        XCTAssertFalse(popover.isHidden)
    }

    func testMovingBarOffWindowDismissesPopover() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26")
        }

        let bar = UIKitNoteFormattingBar(configuration: makeEnabledConfiguration())
        bar.presentPopover()
        let popover = try XCTUnwrap(bar.popoverView)

        bar.willMove(toWindow: nil)

        XCTAssertTrue(popover.isHidden)
    }
}

@available(iOS 26.0, *)
private extension UIKitNoteFormattingBarTests {
    func makeEnabledConfiguration(activeTextStyle: NoteTextStyle = .body) -> NoteFormattingBarConfiguration {
        .init(
            activeTextStyle: activeTextStyle,
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
    }

    func makePopoverView(activeTextStyle: NoteTextStyle) -> UIKitNoteFormattingPopoverView {
        UIKitNoteFormattingPopoverView(configuration: makeEnabledConfiguration(activeTextStyle: activeTextStyle))
    }

    func makeAttachedEditingContext(
        note: NotePayload
    ) async -> (editorViewModel: NotesEditorViewModel, nativeViewModel: NativeNoteEditorViewModel) {
        let context = await makeNotesDetailViewTestContext(note: note)
        let nativeViewModel = context.editorViewModel.makeNativeEditorViewModel()
        context.editorViewModel.attachNativeEditor(nativeViewModel)
        context.editorViewModel.enterEditMode()
        return (context.editorViewModel, nativeViewModel)
    }

    func findDescendant<T: UIView>(
        in view: UIView,
        accessibilityIdentifier: String? = nil
    ) -> T? {
        let identifierMatches = accessibilityIdentifier == nil || view.accessibilityIdentifier == accessibilityIdentifier
        if identifierMatches, let typedView = view as? T {
            return typedView
        }

        for subview in view.subviews {
            if let match: T = findDescendant(in: subview, accessibilityIdentifier: accessibilityIdentifier) {
                return match
            }
        }

        return nil
    }
}
#endif
