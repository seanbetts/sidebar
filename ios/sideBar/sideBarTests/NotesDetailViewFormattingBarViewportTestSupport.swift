#if os(iOS)
import SwiftUI
import UIKit
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, *)
extension NotesFormattingViewportTests {
    func waitForAnchoredEditorTextView(
        in rootView: UIView
    ) async throws -> UIKitNoteTextEditorSurface.AccessoryTextView {
        var resolvedTextView: UIKitNoteTextEditorSurface.AccessoryTextView?
        try await waitUntil(timeout: .seconds(2)) {
            resolvedTextView = self.findTextView(
                in: rootView,
                accessibilityIdentifier: "notes-editor-text-view"
            ) as? UIKitNoteTextEditorSurface.AccessoryTextView
            return resolvedTextView != nil
        }
        return try XCTUnwrap(resolvedTextView)
    }

    func makeFormattingViewportConfiguration(
        for viewModel: NativeNoteEditorViewModel
    ) -> NoteFormattingBarConfiguration {
        NoteFormattingBarConfiguration(
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
            isEnabled: true,
            onTextStyleSelection: { style in
                viewModel.setTextStyle(style)
            },
            onBoldTap: {
                viewModel.setFormatting(.bold, enabled: !viewModel.isFormattingActive(.bold))
            },
            onItalicTap: {
                viewModel.setFormatting(.italic, enabled: !viewModel.isFormattingActive(.italic))
            },
            onUnderlineTap: {
                viewModel.setFormatting(.underline, enabled: !viewModel.isFormattingActive(.underline))
            },
            onStrikethroughTap: {
                viewModel.setFormatting(.strikethrough, enabled: !viewModel.isFormattingActive(.strikethrough))
            }
        )
    }

    func findDescendantButton(in view: UIView, accessibilityIdentifier: String) -> UIButton? {
        if let button = view as? UIButton, button.accessibilityIdentifier == accessibilityIdentifier {
            return button
        }

        for subview in view.subviews {
            if let match = findDescendantButton(in: subview, accessibilityIdentifier: accessibilityIdentifier) {
                return match
            }
        }

        return nil
    }

    func findFormattingPopoverRoot(startingAt view: UIView?) -> UIView? {
        guard let view else { return nil }
        if view.accessibilityIdentifier == "note-formatting-popover" {
            return view
        }

        for subview in view.subviews {
            if let match = findFormattingPopoverRoot(startingAt: subview) {
                return match
            }
        }

        return nil
    }

    func findTextView(in view: UIView?, accessibilityIdentifier: String = "notes-read-text-view") -> UITextView? {
        guard let view else { return nil }
        if let textView = view as? UITextView, textView.accessibilityIdentifier == accessibilityIdentifier {
            return textView
        }

        for subview in view.subviews {
            if let match = findTextView(in: subview, accessibilityIdentifier: accessibilityIdentifier) {
                return match
            }
        }

        return nil
    }

    func complexDecorationViewportDocument() -> NotesSemanticDocument {
        NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .init(type: .heading, content: [.init(text: "Code Blocks", marks: [])]),
                .init(type: .subheading, content: [.init(text: "JavaScript", marks: [])]),
                .init(
                    type: .codeBlock,
                    content: [.init(
                        text: """
                        function greet(name) {
                        console.log('Hello, ${name}!');
                        return true;
                        }
                        """,
                        marks: []
                    )]
                ),
                .init(type: .subheading, content: [.init(text: "Python", marks: [])]),
                .init(
                    type: .codeBlock,
                    content: [.init(
                        text: """
                        def calculate_sum(a, b):
                            return a + b
                        result = calculate_sum(5, 10)
                        print(f"Result: {result}")
                        """,
                        marks: []
                    )]
                ),
                .init(type: .heading, content: [.init(text: "Blockquotes", marks: [])]),
                .init(type: .subheading, content: [.init(text: "Simple Blockquote", marks: [])]),
                .init(
                    type: .blockquote,
                    children: [
                        .paragraph([
                            .init(text: "This is a blockquote.\nIt can span multiple lines.", marks: [])
                        ])
                    ]
                ),
                .paragraph([.init(text: String(repeating: "Trailing paragraph text. ", count: 30), marks: [])])
            ]
        )
    }

    func makeComplexDecorationViewportNote(
        id: String,
        path: String
    ) -> NotePayload {
        let document = complexDecorationViewportDocument()
        return NotePayload(
            id: id,
            name: "Decoration",
            document: document,
            plainText: NotesSemanticDocumentProjection.plainText(from: document),
            path: path,
            modified: nil,
            created: nil
        )
    }

    func anchoredReadViewportAnchorY(
        in textView: UITextView,
        targetOffset: Int
    ) throws -> CGFloat {
        let targetPosition = try XCTUnwrap(
            textView.position(from: textView.beginningOfDocument, offset: targetOffset)
        )
        let initialTargetRect = textView.caretRect(for: targetPosition)
        let viewportHeight = textView.bounds.inset(by: textView.adjustedContentInset).height
        let targetReadOffset = max(
            initialTargetRect.midY - (viewportHeight * 0.55),
            -textView.adjustedContentInset.top
        )
        textView.setContentOffset(CGPoint(x: 0, y: targetReadOffset), animated: false)
        drainNotesHostingRunLoop()
        drainNotesHostingRunLoop()

        let targetRect = textView.caretRect(for: targetPosition)
        let viewport = textView.bounds.inset(by: textView.adjustedContentInset)
        return targetRect.midY - viewport.minY
    }

    func anchoredEditorViewportAnchorY(
        in textView: UIKitNoteTextEditorSurface.AccessoryTextView,
        targetOffset: Int
    ) -> CGFloat? {
        guard let position = textView.position(from: textView.beginningOfDocument, offset: targetOffset) else {
            return nil
        }
        let rect = textView.caretRect(for: position)
        let viewport = textView.visibleViewportRect()
        guard viewport.height > 0 else { return nil }
        return rect.midY - viewport.minY
    }

    func anchoredEditorGlyphRect(
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

    func anchoredEditorBlockquoteRuleRect(
        in textView: UIKitNoteTextEditorSurface.AccessoryTextView,
        nearY: CGFloat
    ) throws -> CGRect {
        let rects = NoteTextBlockquoteDecorationLayout.detachedRuleRects(
            in: textView.attributedText,
            containerWidth: textView.bounds.width,
            textContainerInset: CGSize(
                width: textView.textContainerInset.left,
                height: textView.textContainerInset.top
            )
        )
        return try XCTUnwrap(
            rects.min(by: { abs($0.midY - nearY) < abs($1.midY - nearY) })
        )
    }

    func anchoredEditorSamplePixelColor(
        in view: UIView,
        at point: CGPoint,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> UIColor? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { context in
            view.layer.render(in: context.cgContext)
        }
        guard let cgImage = image.cgImage,
              let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data else {
            XCTFail("Expected rendered pixel data", file: file, line: line)
            return nil
        }

        let pixelX = Int(point.x.rounded(.down))
        let pixelY = Int(point.y.rounded(.down))
        guard pixelX >= 0, pixelX < cgImage.width, pixelY >= 0, pixelY < cgImage.height else {
            XCTFail("Sample point out of bounds: \(point)", file: file, line: line)
            return nil
        }

        let bytes = CFDataGetBytePtr(data)
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let offset = (pixelY * cgImage.bytesPerRow) + (pixelX * bytesPerPixel)
        let alpha = CGFloat(bytes?[offset + 3] ?? 0) / 255
        guard alpha > 0 else { return UIColor(red: 0, green: 0, blue: 0, alpha: 0) }

        return UIColor(
            red: (CGFloat(bytes?[offset] ?? 0) / 255) / alpha,
            green: (CGFloat(bytes?[offset + 1] ?? 0) / 255) / alpha,
            blue: (CGFloat(bytes?[offset + 2] ?? 0) / 255) / alpha,
            alpha: alpha
        )
    }

    func anchoredAssertColorsApproximatelyEqual(
        _ actual: UIColor,
        _ expected: UIColor,
        tolerance: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var actualRed: CGFloat = 0
        var actualGreen: CGFloat = 0
        var actualBlue: CGFloat = 0
        var actualAlpha: CGFloat = 0
        var expectedRed: CGFloat = 0
        var expectedGreen: CGFloat = 0
        var expectedBlue: CGFloat = 0
        var expectedAlpha: CGFloat = 0

        XCTAssertTrue(
            actual.getRed(&actualRed, green: &actualGreen, blue: &actualBlue, alpha: &actualAlpha),
            file: file,
            line: line
        )
        XCTAssertTrue(
            expected.getRed(&expectedRed, green: &expectedGreen, blue: &expectedBlue, alpha: &expectedAlpha),
            file: file,
            line: line
        )

        XCTAssertEqual(actualRed, expectedRed, accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(actualGreen, expectedGreen, accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(actualBlue, expectedBlue, accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(actualAlpha, expectedAlpha, accuracy: tolerance, file: file, line: line)
    }
}
#endif
