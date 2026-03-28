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
    let attributed = SelectableNoteReadView.makePlatformAttributedContent(
        from: NotesSemanticDocumentProjection.document(fromPlainText: plainText),
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

    func testViewportAnchorForScrolledTapStaysRelativeToVisibleReadViewport() throws {
        let plainText = (0..<120)
            .map { index in "Line \(index) body text" }
            .joined(separator: "\n")
        let targetOffset = NSString(string: plainText).range(of: "Line 70 body text").location

        let controller = mount(
            SelectableNoteReadView(
                document: NotesSemanticDocumentProjection.document(fromPlainText: plainText),
                maxContentWidth: 672
            ),
            frame: CGRect(x: 0, y: 0, width: 672, height: 867),
            makeKeyAndVisible: true
        )
        let textView = try XCTUnwrap(findDescendantTextView(in: controller.view))
        let targetPosition = try XCTUnwrap(
            textView.position(from: textView.beginningOfDocument, offset: targetOffset)
        )
        let initialTargetRect = textView.caretRect(for: targetPosition)
        let readViewportHeight = textView.bounds.inset(by: textView.adjustedContentInset).height
        let targetReadOffset = max(
            initialTargetRect.midY - (readViewportHeight * 0.55),
            -textView.adjustedContentInset.top
        )

        textView.setContentOffset(CGPoint(x: 0, y: targetReadOffset), animated: false)
        drainNotesHostingRunLoop()
        drainNotesHostingRunLoop()

        let targetRect = textView.caretRect(for: targetPosition)
        let visibleViewport = CGRect(
            origin: textView.contentOffset,
            size: textView.bounds.size
        ).inset(by: textView.adjustedContentInset)
        let tapPoint = CGPoint(
            x: targetRect.midX,
            y: targetRect.midY
        )
        let expectedViewportAnchorY = targetRect.midY - visibleViewport.minY
        let capturedViewportAnchorY = SelectableNoteReadView.viewportAnchorYForEditingActivation(
            in: textView,
            target: .characterOffset(targetOffset),
            fallbackPoint: tapPoint
        )

        XCTAssertLessThanOrEqual(
            try XCTUnwrap(capturedViewportAnchorY),
            visibleViewport.height + 1,
            "Activation viewport anchor should remain relative to the visible read viewport"
        )
        XCTAssertEqual(
            try XCTUnwrap(capturedViewportAnchorY),
            expectedViewportAnchorY,
            accuracy: 1,
            "tapPoint=\(tapPoint) bounds=\(textView.bounds) contentOffset=\(textView.contentOffset) "
                + "adjustedInset=\(textView.adjustedContentInset) visibleViewport=\(visibleViewport)"
        )
    }

    func testViewportAnchorUsesTapLocationWhenReadViewportResetsBeforeActivation() throws {
        let plainText = (0..<120)
            .map { index in "Line \(index) body text" }
            .joined(separator: "\n")
        let targetOffset = NSString(string: plainText).range(of: "Line 70 body text").location

        let controller = mount(
            SelectableNoteReadView(
                document: NotesSemanticDocumentProjection.document(fromPlainText: plainText),
                maxContentWidth: 672
            ),
            frame: CGRect(x: 0, y: 0, width: 672, height: 867),
            makeKeyAndVisible: true
        )
        let textView = try XCTUnwrap(findDescendantTextView(in: controller.view))
        let targetPosition = try XCTUnwrap(
            textView.position(from: textView.beginningOfDocument, offset: targetOffset)
        )
        let initialTargetRect = textView.caretRect(for: targetPosition)
        let readViewportHeight = textView.bounds.inset(by: textView.adjustedContentInset).height
        let targetReadOffset = max(
            initialTargetRect.midY - (readViewportHeight * 0.55),
            -textView.adjustedContentInset.top
        )

        textView.setContentOffset(CGPoint(x: 0, y: targetReadOffset), animated: false)
        drainNotesHostingRunLoop()
        drainNotesHostingRunLoop()

        let targetRect = textView.caretRect(for: targetPosition)
        let tapPoint = CGPoint(
            x: targetRect.midX - textView.contentOffset.x,
            y: targetRect.midY - textView.contentOffset.y
        )
        let expectedViewportAnchorY = tapPoint.y - textView.adjustedContentInset.top

        textView.setContentOffset(.zero, animated: false)
        drainNotesHostingRunLoop()

        let capturedViewportAnchorY = SelectableNoteReadView.viewportAnchorYForEditingActivation(
            in: textView,
            target: .characterOffset(targetOffset),
            fallbackPoint: tapPoint
        )

        XCTAssertEqual(
            try XCTUnwrap(capturedViewportAnchorY),
            expectedViewportAnchorY,
            accuracy: 1,
            "Viewport anchor should stay tied to the tapped location even if UIKit resets the read offset before activation"
        )
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
    guard let start = textView.position(from: textView.beginningOfDocument, offset: characterIndex),
          let end = textView.position(from: start, offset: 1),
          let textRange = textView.textRange(from: start, to: end) else {
        throw XCTSkip("Unable to resolve tap point")
    }

    let characterRect = textView.firstRect(for: textRange)
    guard characterRect.isNull == false, characterRect.isEmpty == false else {
        throw XCTSkip("Unable to resolve tap point")
    }

    return CGPoint(
        x: characterRect.minX + (characterRect.width * horizontalBias),
        y: characterRect.midY
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
