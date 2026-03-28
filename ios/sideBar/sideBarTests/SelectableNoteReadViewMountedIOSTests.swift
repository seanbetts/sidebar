#if os(iOS)
import SwiftUI
import UIKit
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, *)
final class SelectableNoteReadViewMountedIOSTests: XCTestCase {
    func testWideMountedReadSurfaceKeepsTextViewFullWidthAndCentersReadableColumn() throws {
        let textView = try makeReadTextView(
            plainText: "One\nTwo",
            frame: CGRect(x: 0, y: 0, width: 900, height: 240),
            maxContentWidth: 640
        )
        let expectedHorizontalInset = NoteTextLayout.horizontalPadding + ((900 - 640) / 2)

        XCTAssertEqual(textView.bounds.width, 900, accuracy: 0.5)
        XCTAssertEqual(textView.textContainerInset.left, expectedHorizontalInset, accuracy: 0.5)
        XCTAssertEqual(textView.textContainerInset.right, expectedHorizontalInset, accuracy: 0.5)
    }

    func testMountedReadSurfaceAppliesInitialViewportOffset() throws {
        let plainText = (0..<120)
            .map { index in "Line \(index) body text" }
            .joined(separator: "\n")
        let targetOffset = CGPoint(x: 0, y: 320)
        let textView = try makeReadTextView(
            plainText: plainText,
            frame: CGRect(x: 0, y: 0, width: 672, height: 867),
            maxContentWidth: 672,
            initialViewportOffset: targetOffset
        )

        XCTAssertEqual(textView.accessibilityIdentifier, "notes-read-text-view")
        XCTAssertEqual(textView.contentOffset.y, targetOffset.y, accuracy: 1)
    }

    func testMountedReadSurfaceReportsRestoredViewportOffsetInsteadOfInitialZero() throws {
        let plainText = (0..<120)
            .map { index in "Line \(index) body text" }
            .joined(separator: "\n")
        let targetOffset = CGPoint(x: 0, y: 320)
        var reportedOffsets: [CGPoint] = []
        let controller = UIHostingController(
            rootView: AnyView(
                SelectableNoteReadView(
                    document: NotesSemanticDocumentProjection.document(fromPlainText: plainText),
                    maxContentWidth: 672,
                    initialViewportOffset: targetOffset,
                    onViewportOffsetChange: { reportedOffsets.append($0) }
                )
            )
        )
        let window = makeReadHostingWindow(frame: CGRect(x: 0, y: 0, width: 672, height: 867))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.frame
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        NotesDetailViewTestRetainer.hostingControllers.append(controller)
        NotesDetailViewTestRetainer.hostingWindows.append(window)

        let textView = try XCTUnwrap(findMountedReadTextView(in: controller.view))

        XCTAssertEqual(textView.contentOffset.y, targetOffset.y, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(reportedOffsets.last).y, targetOffset.y, accuracy: 1)
        XCTAssertFalse(
            reportedOffsets.contains(where: { abs($0.y) < 1 }),
            "Mounted read surface should not report a zero viewport offset before restoring \(targetOffset)"
        )
    }

    func testMountedReadSurfaceInitialViewportOffsetIsAppliedOnlyOnce() throws {
        let plainText = (0..<120)
            .map { index in "Line \(index) body text" }
            .joined(separator: "\n")
        let initialOffset = CGPoint(x: 0, y: 320)
        let textView = try makeReadTextView(
            plainText: plainText,
            frame: CGRect(x: 0, y: 0, width: 672, height: 867),
            maxContentWidth: 672,
            initialViewportOffset: initialOffset
        )

        textView.setContentOffset(CGPoint(x: 0, y: 480), animated: false)
        textView.setNeedsLayout()
        textView.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(
            textView.contentOffset.y,
            480,
            accuracy: 1,
            "Mounted read surface should not reapply its initial viewport offset after the user scrolls"
        )
    }

    func testMountedReadSurfaceReanchorsTargetLineWhenLayoutChangesAfterInitialRestore() throws {
        let plainText = (0..<60)
            .map { index in
                "Line \(index) wraps across the readable column with enough repeated words to force line breaks in a narrow layout."
            }
            .joined(separator: "\n")
        let targetOffset = NSString(string: plainText).range(of: "Line 30 wraps").location
        let referenceTextView = try makeReadTextView(
            plainText: plainText,
            frame: CGRect(x: 0, y: 0, width: 672, height: 867),
            maxContentWidth: 672
        )
        let targetPosition = try XCTUnwrap(
            referenceTextView.position(from: referenceTextView.beginningOfDocument, offset: targetOffset)
        )
        let initialTargetRect = referenceTextView.caretRect(for: targetPosition)
        let viewportHeight = referenceTextView.bounds.inset(by: referenceTextView.adjustedContentInset).height
        let targetReadOffset = max(
            initialTargetRect.midY - (viewportHeight * 0.55),
            -referenceTextView.adjustedContentInset.top
        )
        referenceTextView.setContentOffset(CGPoint(x: 0, y: targetReadOffset), animated: false)
        referenceTextView.setNeedsLayout()
        referenceTextView.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let referenceTargetRect = referenceTextView.caretRect(for: targetPosition)
        let expectedViewportAnchorY =
            referenceTargetRect.midY - referenceTextView.bounds.inset(by: referenceTextView.adjustedContentInset).minY

        let controller = UIHostingController(
            rootView: AnyView(
                SelectableNoteReadView(
                    document: NotesSemanticDocumentProjection.document(fromPlainText: plainText),
                    maxContentWidth: 672,
                    initialViewportOffset: CGPoint(x: 0, y: targetReadOffset),
                    initialViewportAnchorTarget: .characterOffset(targetOffset),
                    initialViewportAnchorY: expectedViewportAnchorY,
                    onActivateEditing: { _ in }
                )
            )
        )
        let narrowFrame = CGRect(x: 0, y: 0, width: 420, height: 867)
        let window = makeReadHostingWindow(frame: narrowFrame)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = narrowFrame
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let wideFrame = CGRect(x: 0, y: 0, width: 672, height: 867)
        window.frame = wideFrame
        controller.view.frame = wideFrame
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        NotesDetailViewTestRetainer.hostingControllers.append(controller)
        NotesDetailViewTestRetainer.hostingWindows.append(window)

        let textView = try XCTUnwrap(findMountedReadTextView(in: controller.view))
        let mountedTargetPosition = try XCTUnwrap(
            textView.position(from: textView.beginningOfDocument, offset: targetOffset)
        )
        let mountedTargetRect = textView.caretRect(for: mountedTargetPosition)
        let actualViewportAnchorY = mountedTargetRect.midY - textView.bounds.inset(by: textView.adjustedContentInset).minY

        XCTAssertEqual(
            actualViewportAnchorY,
            expectedViewportAnchorY,
            accuracy: 24,
            "mountedTargetRect=\(mountedTargetRect) contentOffset=\(textView.contentOffset) "
                + "expectedViewportAnchorY=\(expectedViewportAnchorY)"
        )
    }

    func testMountedReadSurfaceKeepsSemanticListTargetAnchoredAcrossLateLayoutPasses() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .init(type: .title, content: [.init(text: "Test Note", marks: [])]),
                .init(type: .heading, content: [.init(text: "Introduction", marks: [])]),
                .paragraph([.init(
                    text: String(repeating: "This is a test note demo paragraph that forces wrapping. ", count: 12),
                    marks: []
                )]),
                .init(type: .heading, content: [.init(text: "Checklist", marks: [])]),
                .init(
                    type: .unorderedList,
                    children: [
                        .init(type: .listItem, content: [.init(text: "First Item", marks: [])]),
                        .init(type: .listItem, content: [.init(text: "Second Item", marks: [])]),
                        .init(type: .listItem, content: [.init(text: "Third Item", marks: [])]),
                        .init(type: .listItem, content: [.init(text: "Fourth Item", marks: [])]),
                        .init(type: .listItem, content: [.init(text: "Fifth Item", marks: [])])
                    ]
                ),
                .paragraph([.init(
                    text: String(repeating: "Trailing paragraph text keeps the document tall enough for restoration. ", count: 18),
                    marks: []
                )])
            ]
        )
        let frame = CGRect(x: 0, y: 0, width: 672, height: 867)
        let referenceTextView = try makeReadTextView(
            document: document,
            frame: frame,
            maxContentWidth: frame.width
        )
        let targetOffset = NSString(string: referenceTextView.attributedText.string)
            .range(of: "Fifth Item").location
        let targetPosition = try XCTUnwrap(
            referenceTextView.position(from: referenceTextView.beginningOfDocument, offset: targetOffset)
        )
        let initialTargetRect = referenceTextView.caretRect(for: targetPosition)
        let viewportHeight = referenceTextView.bounds.inset(by: referenceTextView.adjustedContentInset).height
        let targetReadOffset = max(
            initialTargetRect.midY - (viewportHeight * 0.55),
            -referenceTextView.adjustedContentInset.top
        )
        referenceTextView.setContentOffset(CGPoint(x: 0, y: targetReadOffset), animated: false)
        referenceTextView.setNeedsLayout()
        referenceTextView.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let referenceTargetRect = referenceTextView.caretRect(for: targetPosition)
        let expectedViewportAnchorY =
            referenceTargetRect.midY - referenceTextView.bounds.inset(by: referenceTextView.adjustedContentInset).minY

        let textView = try makeReadTextView(
            document: document,
            frame: frame,
            maxContentWidth: frame.width,
            initialViewportOffset: CGPoint(x: 0, y: targetReadOffset),
            initialViewportAnchorTarget: .characterOffset(targetOffset),
            initialViewportAnchorY: expectedViewportAnchorY
        )

        for _ in 0..<6 {
            textView.setNeedsLayout()
            textView.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }

        let mountedTargetPosition = try XCTUnwrap(
            textView.position(from: textView.beginningOfDocument, offset: targetOffset)
        )
        let mountedTargetRect = textView.caretRect(for: mountedTargetPosition)
        let actualViewportAnchorY =
            mountedTargetRect.midY - textView.bounds.inset(by: textView.adjustedContentInset).minY

        XCTAssertEqual(
            actualViewportAnchorY,
            expectedViewportAnchorY,
            accuracy: 6,
            "contentOffset=\(textView.contentOffset) contentSize=\(textView.contentSize) "
                + "mountedTargetRect=\(mountedTargetRect) expectedViewportAnchorY=\(expectedViewportAnchorY)"
        )
    }

}

@MainActor
private func findMountedReadTextView(in view: UIView) -> UITextView? {
    if let textView = view as? UITextView {
        return textView
    }

    for subview in view.subviews {
        if let match = findMountedReadTextView(in: subview) {
            return match
        }
    }

    return nil
}

@MainActor
private func makeReadHostingWindow(frame: CGRect) -> UIWindow {
    guard let windowScene = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first else {
        fatalError("Expected UIWindowScene for SelectableNoteReadViewMountedIOSTests")
    }

    let window = UIWindow(windowScene: windowScene)
    window.frame = frame
    return window
}
#endif
