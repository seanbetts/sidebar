import XCTest
#if os(macOS)
import AppKit
#elseif os(iOS)
import SwiftUI
import UIKit
#endif
@testable import sideBar

#if os(macOS)
@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class SelectableNoteReadActivationTests: XCTestCase {
    func testNonLinkClickActivatesEditingWithCharacterOffsetTarget() async throws {
        var capturedTarget: NotesEditorViewModel.PendingEditSelectionTarget?
        let textView = try makeReadActivationTextView(
            plainText: "Hello world",
            frame: NSRect(x: 0, y: 0, width: 320, height: 120)
        ) { target in
            capturedTarget = target
        }
        let clickPoint = try clickPoint(
            in: textView,
            characterIndex: 0,
            horizontalBias: 0.05
        )

        capturedTarget = nil
        textView.mouseDown(with: try makeActivationMouseEvent(
            type: .leftMouseDown,
            location: clickPoint,
            timestamp: 0,
            eventNumber: 0,
            pressure: 1
        ))
        textView.mouseUp(with: try makeActivationMouseEvent(
            type: .leftMouseUp,
            location: clickPoint,
            timestamp: 0.1,
            eventNumber: 1,
            pressure: 0
        ))

        XCTAssertNil(capturedTarget)
        for _ in 0..<3 {
            drainNotesHostingRunLoop()
            await Task.yield()
        }
        await waitUntil(timeout: .milliseconds(150)) {
            capturedTarget == .characterOffset(0)
        }
        XCTAssertEqual(capturedTarget, .characterOffset(0))
    }

    func testLinkClickDoesNotActivateEditing() throws {
        var capturedTarget: NotesEditorViewModel.PendingEditSelectionTarget?
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([
                    .init(text: "https://example.com", marks: [])
                ])
            ]
        )
        let attributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: 16
        )
        let expectedURL = try XCTUnwrap(URL(string: "https://example.com"))

        let textView = SelectableNoteReadView.makePlatformTextView(
            attributedContent: attributed,
            onActivateEditing: { target in
                capturedTarget = target
            }
        )
        textView.frame = NSRect(x: 0, y: 0, width: 320, height: 120)
        let linkValue = textView.textStorage?.attribute(
            NSAttributedString.Key.link,
            at: 0,
            effectiveRange: nil
        ) as? URL
        XCTAssertEqual(linkValue, expectedURL)

        let clickPoint = try clickPoint(
            in: textView,
            characterIndex: 0,
            horizontalBias: 0.5
        )

        capturedTarget = nil
        textView.mouseDown(with: try makeActivationMouseEvent(
            type: .leftMouseDown,
            location: clickPoint,
            timestamp: 0,
            eventNumber: 0,
            pressure: 1
        ))
        textView.mouseUp(with: try makeActivationMouseEvent(
            type: .leftMouseUp,
            location: clickPoint,
            timestamp: 0.1,
            eventNumber: 1,
            pressure: 0
        ))

        XCTAssertNil(capturedTarget)
    }
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
private func makeReadActivationTextView(
    plainText: String,
    frame: NSRect,
    onActivateEditing: @escaping (NotesEditorViewModel.PendingEditSelectionTarget) -> Void
) throws -> NSTextView {
    let document = NotesSemanticDocumentProjection.document(fromPlainText: plainText)
    let attributed = SelectableNoteReadView.makePlatformAttributedContent(
        from: document,
        baseFontSize: 16
    )
    let textView = SelectableNoteReadView.makePlatformTextView(
        attributedContent: attributed,
        onActivateEditing: onActivateEditing
    )
    textView.frame = frame
    textView.layoutSubtreeIfNeeded()
    return textView
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
private func clickPoint(
    in textView: NSTextView,
    characterIndex: Int,
    horizontalBias: CGFloat
) throws -> NSPoint {
    guard let layoutManager = textView.layoutManager,
          let textContainer = textView.textContainer,
          characterIndex < textView.string.utf16.count else {
        throw XCTSkip("Unable to resolve click point")
    }

    textContainer.containerSize = NSSize(
        width: textView.bounds.width,
        height: CGFloat.greatestFiniteMagnitude
    )
    layoutManager.ensureLayout(for: textContainer)
    let glyphRange = layoutManager.glyphRange(
        forCharacterRange: NSRange(location: characterIndex, length: 1),
        actualCharacterRange: nil
    )
    let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
    return NSPoint(
        x: textView.textContainerInset.width + glyphRect.minX + (glyphRect.width * horizontalBias),
        y: textView.textContainerInset.height + glyphRect.midY
    )
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
private func makeActivationMouseEvent(
    type: NSEvent.EventType,
    location: NSPoint,
    timestamp: TimeInterval,
    eventNumber: Int,
    pressure: Float
) throws -> NSEvent {
    try XCTUnwrap(
        NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: timestamp,
            windowNumber: 0,
            context: nil,
            eventNumber: eventNumber,
            clickCount: 1,
            pressure: pressure
        )
    )
}
#endif

#if os(iOS)
@MainActor
@available(iOS 26.0, *)
final class SelectableNoteReadActivationIOSTests: NotesDetailViewHostingTestCase {
    func testLinkTapDoesNotActivateEditing() throws {
        var capturedTarget: NotesEditorViewModel.PendingEditSelectionTarget?
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([
                    .init(text: "https://example.com", marks: [])
                ])
            ]
        )

        let controller = mount(
            SelectableNoteReadView(
                document: document,
                maxContentWidth: 320,
                onActivateEditing: { target in
                    capturedTarget = target
                }
            ),
            frame: CGRect(x: 0, y: 0, width: 320, height: 180),
            makeKeyAndVisible: true
        )
        let textView = try XCTUnwrap(findDescendantTextView(in: controller.view))
        let containerView = try XCTUnwrap(textView.superview)
        let expectedURL = try XCTUnwrap(URL(string: "https://example.com"))
        let linkValue = textView.attributedText.attribute(
            .link,
            at: 0,
            effectiveRange: nil
        ) as? URL
        XCTAssertEqual(linkValue, expectedURL)

        let tapPoint = try localTapPoint(
            in: textView,
            characterIndex: 0,
            horizontalBias: 0.5
        )
        let recognizer = ReadActivationTapGestureRecognizer(location: tapPoint)
        recognizer.setValue(UIGestureRecognizer.State.ended.rawValue, forKey: "state")

        containerView.perform(
            NSSelectorFromString("handleActivationTapGesture:"),
            with: recognizer
        )

        XCTAssertNil(capturedTarget)
    }
}

@MainActor
@available(iOS 26.0, *)
private func localTapPoint(
    in textView: UITextView,
    characterIndex: Int,
    horizontalBias: CGFloat
) throws -> CGPoint {
    guard characterIndex < textView.attributedText.length else {
        throw XCTSkip("Unable to resolve tap point")
    }
    let layoutManager = textView.layoutManager
    let textContainer = textView.textContainer

    textContainer.size = CGSize(
        width: textView.bounds.width - textView.textContainerInset.left - textView.textContainerInset.right,
        height: .greatestFiniteMagnitude
    )
    layoutManager.ensureLayout(for: textContainer)
    let glyphRange = layoutManager.glyphRange(
        forCharacterRange: NSRange(location: characterIndex, length: 1),
        actualCharacterRange: nil
    )
    let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
    return CGPoint(
        x: textView.textContainerInset.left + glyphRect.minX + (glyphRect.width * horizontalBias),
        y: textView.textContainerInset.top + glyphRect.midY
    )
}

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

private final class ReadActivationTapGestureRecognizer: UITapGestureRecognizer, @unchecked Sendable {
    private let testLocation: CGPoint

    init(location: CGPoint) {
        self.testLocation = location
        super.init(target: nil, action: nil)
    }

    override func location(in view: UIView?) -> CGPoint {
        testLocation
    }
}
#endif
