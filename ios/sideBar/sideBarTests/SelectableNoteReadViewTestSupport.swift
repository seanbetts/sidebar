import SwiftUI
import XCTest
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif
@testable import sideBar

#if os(macOS)
@MainActor
@available(iOS 26.0, macOS 26.0, *)
func nonLinkClickPoint(
    in textView: NSTextView,
    characterIndex: Int,
    horizontalBias: CGFloat = 0.5
) -> NSPoint? {
    guard let layoutManager = textView.layoutManager,
          let textContainer = textView.textContainer,
          characterIndex < textView.string.utf16.count else {
        return nil
    }

    textContainer.containerSize = NSSize(width: textView.bounds.width, height: CGFloat.greatestFiniteMagnitude)
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
func makeMouseEvent(
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

@MainActor
@available(iOS 26.0, macOS 26.0, *)
func makeSelectionPoint(
    in textView: NSTextView,
    characterIndex: Int,
    horizontalBias: CGFloat
) throws -> NSPoint {
    try XCTUnwrap(
        nonLinkClickPoint(
            in: textView,
            characterIndex: characterIndex,
            horizontalBias: horizontalBias
        )
    )
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
func performDragSelection(
    in textView: NSTextView,
    from start: NSPoint,
    to end: NSPoint
) throws {
    let mouseDown = try makeMouseEvent(
        type: .leftMouseDown,
        location: start,
        timestamp: 0,
        eventNumber: 0,
        pressure: 1
    )
    let mouseDragged = try makeMouseEvent(
        type: .leftMouseDragged,
        location: end,
        timestamp: 0.1,
        eventNumber: 1,
        pressure: 1
    )
    let mouseUp = try makeMouseEvent(
        type: .leftMouseUp,
        location: end,
        timestamp: 0.2,
        eventNumber: 2,
        pressure: 0
    )

    textView.mouseDown(with: mouseDown)
    textView.mouseDragged(with: mouseDragged)
    textView.mouseUp(with: mouseUp)
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
func exportedSelection(from textView: NSTextView) throws -> AttributedString {
    let exported = try XCTUnwrap(
        textView.attributedSubstring(
            forProposedRange: textView.selectedRange(),
            actualRange: nil
        )
    )
    return AttributedString(exported)
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
func lineGap(
    in textView: NSTextView,
    fromCharacterAt firstIndex: Int,
    toCharacterAt secondIndex: Int
) throws -> CGFloat {
    let firstRect = try glyphRect(in: textView, characterIndex: firstIndex)
    let secondRect = try glyphRect(in: textView, characterIndex: secondIndex)
    return secondRect.minY - firstRect.maxY
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
func glyphRect(
    in textView: NSTextView,
    characterIndex: Int
) throws -> NSRect {
    guard let layoutManager = textView.layoutManager,
          let textContainer = textView.textContainer else {
        throw XCTSkip("Missing text layout infrastructure")
    }

    textContainer.containerSize = NSSize(width: textView.bounds.width, height: CGFloat.greatestFiniteMagnitude)
    layoutManager.ensureLayout(for: textContainer)
    let glyphRange = layoutManager.glyphRange(
        forCharacterRange: NSRange(location: characterIndex, length: 1),
        actualCharacterRange: nil
    )
    return layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
func mountEditorTextView(
    plainText: String,
    baseFontSize: CGFloat,
    frame: NSRect
) throws -> NSTextView {
    let nativeViewModel = NativeNoteEditorViewModel()
    nativeViewModel.setBaseFontSize(baseFontSize)
    nativeViewModel.loadText(plainText)

    let controller = NSHostingController(
        rootView: AnyView(
            SwiftUINoteTextEditorSurface(
                viewModel: nativeViewModel,
                maxContentWidth: frame.width,
                isEditable: true
            )
        )
    )
    let window = NSWindow(
        contentRect: frame,
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    window.contentViewController = controller
    window.orderFront(nil)
    let rootView = controller.view
    rootView.frame = frame
    rootView.layoutSubtreeIfNeeded()

    return try XCTUnwrap(findDescendantTextView(in: rootView))
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
func makeReadTextView(
    plainText: String,
    frame: NSRect,
    baseFontSize: CGFloat = 16
) throws -> NSTextView {
    let document = NotesSemanticDocumentProjection.document(fromPlainText: plainText)
    let attributed = SelectableNoteReadView.makePlatformAttributedContent(
        from: document,
        baseFontSize: baseFontSize
    )
    let textView = SelectableNoteReadView.makePlatformTextView(attributedContent: attributed)
    textView.frame = frame
    textView.layoutSubtreeIfNeeded()
    return textView
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
func lineEndOverflowClickPoint(
    in textView: NSTextView,
    characterIndex: Int
) throws -> NSPoint {
    let rect = try glyphRect(in: textView, characterIndex: characterIndex)
    return NSPoint(
        x: textView.textContainerInset.width + rect.maxX + 40,
        y: textView.textContainerInset.height + rect.midY
    )
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
func belowContentClickPoint(
    in textView: NSTextView,
    characterIndex: Int
) throws -> NSPoint {
    let rect = try glyphRect(in: textView, characterIndex: characterIndex)
    return NSPoint(
        x: textView.textContainerInset.width + rect.midX,
        y: textView.textContainerInset.height + rect.maxY + rect.height + 20
    )
}

@MainActor
func findDescendantTextView(in view: NSView) -> NSTextView? {
    if let textView = view as? NSTextView {
        return textView
    }

    for subview in view.subviews {
        if let match = findDescendantTextView(in: subview) {
            return match
        }
    }

    return nil
}
#elseif os(iOS)
@MainActor
@available(iOS 26.0, macOS 26.0, *)
func makeReadTextView(
    plainText: String,
    frame: CGRect,
    baseFontSize: CGFloat = 16
) throws -> UITextView {
    let document = NotesSemanticDocumentProjection.document(fromPlainText: plainText)
    let controller = UIHostingController(
        rootView: AnyView(
            SelectableNoteReadView(
                document: document,
                maxContentWidth: frame.width,
                onActivateEditing: { _ in }
            )
        )
    )
    let window = makeHostingWindow(frame: frame)
    window.rootViewController = controller
    window.makeKeyAndVisible()
    controller.view.frame = frame
    controller.view.setNeedsLayout()
    controller.view.layoutIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    NotesDetailViewTestRetainer.hostingControllers.append(controller)
    NotesDetailViewTestRetainer.hostingWindows.append(window)

    let textView = try XCTUnwrap(findDescendantTextView(in: controller.view))
    if abs(baseFontSize - NoteTextTypography.defaultBodyFontSize) > 0.001 {
        textView.attributedText = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: baseFontSize
        )
        textView.setNeedsLayout()
        textView.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    return textView
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
func lineEndOverflowClickPoint(
    in textView: UITextView,
    characterIndex: Int
) throws -> CGPoint {
    let rect = try characterRect(in: textView, characterIndex: characterIndex)
    return CGPoint(x: rect.maxX + 40, y: rect.midY)
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
func belowContentClickPoint(
    in textView: UITextView,
    characterIndex: Int
) throws -> CGPoint {
    let rect = try characterRect(in: textView, characterIndex: characterIndex)
    return CGPoint(x: rect.midX, y: rect.maxY + rect.height + 20)
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
func characterRect(
    in textView: UITextView,
    characterIndex: Int
) throws -> CGRect {
    let length = textView.attributedText.length
    guard characterIndex >= 0, characterIndex < length else {
        throw XCTSkip("Character index out of bounds")
    }
    let start = try XCTUnwrap(
        textView.position(from: textView.beginningOfDocument, offset: characterIndex)
    )
    let end = try XCTUnwrap(textView.position(from: start, offset: 1))
    let range = try XCTUnwrap(textView.textRange(from: start, to: end))
    return textView.firstRect(for: range)
}

@MainActor
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

@MainActor
private func makeHostingWindow(frame: CGRect) -> UIWindow {
    guard let windowScene = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first else {
        fatalError("Expected UIWindowScene for SelectableNoteReadViewTests")
    }

    let window = UIWindow(windowScene: windowScene)
    window.frame = frame
    return window
}
#endif
