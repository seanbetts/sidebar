import SwiftUI
import XCTest
@testable import sideBar

#if os(macOS)
@MainActor
extension NotesDetailViewMacOSStabilityTests {
    func testMountedDetailToggleKeepsLongParagraphWrappedOnMacOS() async throws {
        let longParagraph = Array(repeating: "Long wrapped segment", count: 80).joined(separator: " ")
        let lastCharacterIndex = max(longParagraph.utf16.count - 1, 0)
        let context = await makeNotesDetailViewTestContext(
            note: makeTestNote(id: "wrapping-note", plainText: longParagraph)
        )
        let environment = makeNotesDetailTestEnvironment()
        let controller = mount(
            context.makeView().environmentObject(environment),
            frame: CGRect(x: 0, y: 0, width: 420, height: 700)
        )
        let mountedView = controller.view
        mountedView.layoutSubtreeIfNeeded()
        mountedView.window?.contentView?.layoutSubtreeIfNeeded()
        drainNotesHostingRunLoop()

        let initialReadTextView = try XCTUnwrap(findDescendantTextView(in: mountedView))
        XCTAssertFalse(initialReadTextView.isEditable)
        try assertMountedTextViewWrapsLongParagraph(
            initialReadTextView,
            lastCharacterIndex: lastCharacterIndex
        )

        context.makeView().activateReadSurfaceEditing(at: .characterOffset(0))

        let editorTextView = try await waitForMountedTextView(in: mountedView) { textView in
            textView.isEditable
        }
        try assertMountedTextViewWrapsLongParagraph(
            editorTextView,
            lastCharacterIndex: lastCharacterIndex
        )

        context.makeView().handleCloseShortcut()

        let restoredReadTextView = try await waitForMountedTextView(in: mountedView) { textView in
            textView.isEditable == false
        }
        try assertMountedTextViewWrapsLongParagraph(
            restoredReadTextView,
            lastCharacterIndex: lastCharacterIndex
        )
    }

    func testMountedDetailEntryTransitionKeepsLongParagraphWrappedOnMacOS() async throws {
        let longParagraph = Array(repeating: "Long wrapped segment", count: 80).joined(separator: " ")
        let lastCharacterIndex = max(longParagraph.utf16.count - 1, 0)
        let context = await makeNotesDetailViewTestContext(
            note: makeTestNote(id: "entry-wrap-note", plainText: longParagraph)
        )
        let environment = makeNotesDetailTestEnvironment()
        let controller = mount(
            context.makeView().environmentObject(environment),
            frame: CGRect(x: 0, y: 0, width: 420, height: 700)
        )
        let mountedView = controller.view
        mountedView.layoutSubtreeIfNeeded()
        mountedView.window?.contentView?.layoutSubtreeIfNeeded()
        drainNotesHostingRunLoop()

        context.makeView().activateReadSurfaceEditing(at: .characterOffset(0))

        try assertMountedVisibleTextViewsStayWrapped(
            in: mountedView,
            lastCharacterIndex: lastCharacterIndex,
            samples: 24
        )
    }

    func testEditEntryBootstrapKeepsHiddenEditorWrappedOnMacOS() async throws {
        let paragraphs = (0..<60).map { index in
            "Paragraph \(index) " + Array(repeating: "Long wrapped segment", count: 12).joined(separator: " ")
        }
        let documentText = paragraphs.joined(separator: "\n\n")
        let lastCharacterIndex = max(documentText.utf16.count - 1, 0)
        let harness = await MountedNotesDetailHarness(
            note: makeTestNote(plainText: documentText)
        )
        defer { harness.dispose() }
        harness.mount()
        await harness.settle()

        let initialReadTextView = try await waitForMountedTextView(in: harness.mountedView) { textView in
            textView.isEditable == false
        }
        let clipView = try XCTUnwrap(initialReadTextView.enclosingScrollView?.contentView)
        clipView.scroll(to: NSPoint(x: 0, y: 700))
        initialReadTextView.enclosingScrollView?.reflectScrolledClipView(clipView)
        harness.mountedView.layoutSubtreeIfNeeded()
        harness.mountedWindow.contentView?.layoutSubtreeIfNeeded()
        drainNotesHostingRunLoop()

        harness.context.makeView().activateReadSurfaceEditing(at: .characterOffset(525))

        var hiddenEditorTextView: NSTextView?
        await waitUntil(timeout: .seconds(2)) {
            guard harness.context.editorViewModel.isHoldingReadSurfaceDuringEditEntry else { return false }
            hiddenEditorTextView = findDescendantTextViews(in: harness.mountedView).first(where: { $0.isEditable })
            return hiddenEditorTextView != nil
        }

        let editorTextView = try XCTUnwrap(hiddenEditorTextView)
        try assertMountedTextViewWrapsLongParagraph(
            editorTextView,
            lastCharacterIndex: lastCharacterIndex
        )
    }

    func testDesktopWidthEntryTransitionKeepsWindowVisibleTextViewsWrappedOnMacOS() async throws {
        let paragraphs = (0..<60).map { index in
            "Paragraph \(index) " + Array(repeating: "Long wrapped segment", count: 12).joined(separator: " ")
        }
        let documentText = paragraphs.joined(separator: "\n\n")
        let lastCharacterIndex = max(documentText.utf16.count - 1, 0)
        let context = await makeNotesDetailViewTestContext(
            note: makeTestNote(id: "desktop-entry-wrap-note", plainText: documentText)
        )
        let environment = makeNotesDetailTestEnvironment()
        let controller = mount(
            context.makeView().environmentObject(environment),
            frame: CGRect(x: 0, y: 0, width: 1077.5, height: 1376)
        )
        let mountedView = controller.view
        let windowRootView = try XCTUnwrap(controller.view.window?.contentView)
        mountedView.layoutSubtreeIfNeeded()
        windowRootView.layoutSubtreeIfNeeded()
        drainNotesHostingRunLoop()

        let initialReadTextView = try await waitForMountedTextView(in: windowRootView) { textView in
            textView.isEditable == false
        }
        let clipView = try XCTUnwrap(initialReadTextView.enclosingScrollView?.contentView)
        clipView.scroll(to: NSPoint(x: 0, y: 700))
        initialReadTextView.enclosingScrollView?.reflectScrolledClipView(clipView)
        windowRootView.layoutSubtreeIfNeeded()
        drainNotesHostingRunLoop()

        context.makeView().activateReadSurfaceEditing(at: .characterOffset(354))

        try assertMountedVisibleTextViewsStayWrapped(
            in: windowRootView,
            lastCharacterIndex: lastCharacterIndex,
            samples: 24
        )
    }

    func testDesktopWidthEditEntryHoldKeepsEditorWindowTextViewHiddenOnMacOS() async throws {
        let paragraphs = (0..<60).map { index in
            "Paragraph \(index) " + Array(repeating: "Long wrapped segment", count: 12).joined(separator: " ")
        }
        let documentText = paragraphs.joined(separator: "\n\n")
        let context = await makeNotesDetailViewTestContext(
            note: makeTestNote(id: "desktop-entry-hidden-editor-note", plainText: documentText)
        )
        let environment = makeNotesDetailTestEnvironment()
        let controller = mount(
            context.makeView().environmentObject(environment),
            frame: CGRect(x: 0, y: 0, width: 1077.5, height: 1376)
        )
        let windowRootView = try XCTUnwrap(controller.view.window?.contentView)
        windowRootView.layoutSubtreeIfNeeded()
        drainNotesHostingRunLoop()

        let initialReadTextView = try await waitForMountedTextView(in: windowRootView) { textView in
            textView.isEditable == false
        }
        let clipView = try XCTUnwrap(initialReadTextView.enclosingScrollView?.contentView)
        clipView.scroll(to: NSPoint(x: 0, y: 700))
        initialReadTextView.enclosingScrollView?.reflectScrolledClipView(clipView)
        windowRootView.layoutSubtreeIfNeeded()
        drainNotesHostingRunLoop()

        context.makeView().activateReadSurfaceEditing(at: .characterOffset(354))

        var heldEditorTextView: NSTextView?
        await waitUntil(timeout: .seconds(2)) {
            guard context.editorViewModel.isHoldingReadSurfaceDuringEditEntry else { return false }
            heldEditorTextView = findDescendantTextViews(in: windowRootView).first(where: { $0.isEditable })
            return heldEditorTextView != nil
        }

        let editorTextView = try XCTUnwrap(heldEditorTextView)
        XCTAssertLessThan(
            effectiveMountedAlpha(of: editorTextView),
            0.1,
            "Expected the AppKit editor surface to stay visually hidden until the read-entry hold is released."
        )
    }

    func testMountedDetailExitTransitionKeepsLongParagraphWrappedOnMacOS() async throws {
        let longParagraph = Array(repeating: "Long wrapped segment", count: 80).joined(separator: " ")
        let lastCharacterIndex = max(longParagraph.utf16.count - 1, 0)
        let context = await makeNotesDetailViewTestContext(
            note: makeTestNote(id: "exit-wrap-note", plainText: longParagraph)
        )
        let environment = makeNotesDetailTestEnvironment()
        let controller = mount(
            context.makeView().environmentObject(environment),
            frame: CGRect(x: 0, y: 0, width: 420, height: 700)
        )
        let mountedView = controller.view
        mountedView.layoutSubtreeIfNeeded()
        mountedView.window?.contentView?.layoutSubtreeIfNeeded()
        drainNotesHostingRunLoop()

        context.makeView().activateReadSurfaceEditing(at: .characterOffset(0))
        _ = try await waitForMountedTextView(in: mountedView) { textView in
            textView.isEditable
        }
        await waitUntil(timeout: .seconds(2)) {
            context.editorViewModel.isHoldingReadSurfaceDuringEditEntry == false
        }

        context.makeView().handleCloseShortcut()

        try assertMountedVisibleTextViewsStayWrapped(
            in: mountedView,
            lastCharacterIndex: lastCharacterIndex,
            samples: 24
        )
    }

    func testEditToReadExitHoldKeepsEditorVisibleDuringMacOSReadBootstrap() async throws {
        let harness = await MountedNotesDetailHarness(
            note: makeTestNote(plainText: Array(repeating: "Line body", count: 80).joined(separator: "\n"))
        )
        defer { harness.dispose() }
        harness.mount()
        await harness.settle()

        harness.context.makeView().activateReadSurfaceEditing(at: .characterOffset(0))

        _ = try await waitForMountedTextView(in: harness.mountedView) { textView in
            textView.isEditable && harness.mountedWindow.firstResponder === textView
        }
        await waitUntil(timeout: .seconds(2)) {
            harness.context.editorViewModel.isHoldingReadSurfaceDuringEditEntry == false
        }

        harness.context.makeView().handleCloseShortcut()

        var mountedTextViewsDuringExit: [NSTextView] = []
        await waitUntil(timeout: .seconds(2)) {
            guard harness.context.editorViewModel.presentationMode == .read else { return false }
            mountedTextViewsDuringExit = findDescendantTextViews(in: harness.mountedView)
            let hasReadSurface = mountedTextViewsDuringExit.contains(where: { !$0.isEditable })
            let hasHeldEditor = mountedTextViewsDuringExit.contains(where: { $0.isEditable })
            return hasReadSurface && hasHeldEditor
        }

        let heldReadTextView = try XCTUnwrap(mountedTextViewsDuringExit.first(where: { !$0.isEditable }))
        let heldEditorTextView = try XCTUnwrap(
            mountedTextViewsDuringExit.first(where: { $0.isEditable && effectiveMountedAlpha(of: $0) > 0.1 })
        )
        XCTAssertTrue(
            mountedTextViewsDuringExit.contains(where: { $0.isEditable }),
            "Expected an editable AppKit editor surface to stay mounted briefly while the read surface boots on macOS."
        )
        XCTAssertGreaterThan(effectiveMountedAlpha(of: heldEditorTextView), 0.9)
        XCTAssertLessThan(effectiveMountedAlpha(of: heldReadTextView), 0.1)

        await waitUntil(timeout: .seconds(2)) {
            let mountedTextViews = findDescendantTextViews(in: harness.mountedView)
            guard mountedTextViews.contains(where: { $0.isEditable && effectiveMountedAlpha(of: $0) > 0.1 }) == false,
                  let restoredReadTextView = findDescendantTextViews(in: harness.mountedView)
                    .first(where: { !$0.isEditable }) else {
                return false
            }
            return effectiveMountedAlpha(of: restoredReadTextView) > 0.9
        }
    }

    func testEditToReadExitBootstrapKeepsHiddenReadSurfaceWrappedOnMacOS() async throws {
        let paragraphs = (0..<60).map { index in
            "Paragraph \(index) " + Array(repeating: "Long wrapped segment", count: 12).joined(separator: " ")
        }
        let documentText = paragraphs.joined(separator: "\n\n")
        let lastCharacterIndex = max(documentText.utf16.count - 1, 0)
        let harness = await MountedNotesDetailHarness(
            note: makeTestNote(plainText: documentText)
        )
        defer { harness.dispose() }
        harness.mount()
        await harness.settle()

        let initialReadTextView = try await waitForMountedTextView(in: harness.mountedView) { textView in
            textView.isEditable == false
        }
        let clipView = try XCTUnwrap(initialReadTextView.enclosingScrollView?.contentView)
        clipView.scroll(to: NSPoint(x: 0, y: 700))
        initialReadTextView.enclosingScrollView?.reflectScrolledClipView(clipView)
        harness.mountedView.layoutSubtreeIfNeeded()
        harness.mountedWindow.contentView?.layoutSubtreeIfNeeded()
        drainNotesHostingRunLoop()

        harness.context.makeView().activateReadSurfaceEditing(at: .characterOffset(660))

        _ = try await waitForMountedTextView(in: harness.mountedView) { textView in
            textView.isEditable && harness.mountedWindow.firstResponder === textView
        }
        await waitUntil(timeout: .seconds(2)) {
            harness.context.editorViewModel.isHoldingReadSurfaceDuringEditEntry == false
        }

        harness.context.makeView().handleCloseShortcut()

        var hiddenReadTextView: NSTextView?
        await waitUntil(timeout: .seconds(2)) {
            guard harness.context.editorViewModel.presentationMode == .read else { return false }
            let mountedTextViews = findDescendantTextViews(in: harness.mountedView)
            hiddenReadTextView = mountedTextViews.first(where: { !$0.isEditable })
            let heldEditor = mountedTextViews.first(where: { $0.isEditable && effectiveMountedAlpha(of: $0) > 0.1 })
            return hiddenReadTextView != nil && heldEditor != nil
        }

        let readTextView = try XCTUnwrap(hiddenReadTextView)
        try assertMountedTextViewWrapsLongParagraph(
            readTextView,
            lastCharacterIndex: lastCharacterIndex
        )
    }
}

@MainActor
private func waitForMountedTextView(
    in rootView: NSView,
    matching predicate: @escaping (NSTextView) -> Bool
) async throws -> NSTextView {
    var resolvedTextView: NSTextView?
    await waitUntil(timeout: .seconds(2)) {
        guard let textView = findDescendantTextView(in: rootView), predicate(textView) else {
            return false
        }
        resolvedTextView = textView
        return true
    }
    return try XCTUnwrap(resolvedTextView)
}

@MainActor
private func assertMountedTextViewWrapsLongParagraph(
    _ textView: NSTextView,
    lastCharacterIndex: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    textView.layoutSubtreeIfNeeded()
    textView.enclosingScrollView?.layoutSubtreeIfNeeded()
    textView.window?.contentView?.layoutSubtreeIfNeeded()
    drainNotesHostingRunLoop()

    let firstCharacterRect = try glyphRect(in: textView, characterIndex: 0)
    let lastCharacterRect = try glyphRect(in: textView, characterIndex: lastCharacterIndex)

    XCTAssertGreaterThan(
        lastCharacterRect.minY,
        firstCharacterRect.minY + 1,
        "Expected the mounted note surface to wrap long paragraphs instead of laying them out on one overflowing line.",
        file: file,
        line: line
    )
}

@MainActor
private func assertMountedVisibleTextViewsStayWrapped(
    in rootView: NSView,
    lastCharacterIndex: Int,
    samples: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    for sampleIndex in 0..<samples {
        rootView.layoutSubtreeIfNeeded()
        rootView.window?.contentView?.layoutSubtreeIfNeeded()
        if sampleIndex > 0 {
            drainNotesHostingRunLoop()
        }

        let visibleTextViews = findDescendantTextViews(in: rootView)
            .filter(mountedTextViewIsVisible(_:))
        XCTAssertFalse(
            visibleTextViews.isEmpty,
            "Expected at least one visible text view during transition sample \(sampleIndex).",
            file: file,
            line: line
        )
        for textView in visibleTextViews {
            try assertMountedTextViewWrapsLongParagraph(
                textView,
                lastCharacterIndex: lastCharacterIndex,
                file: file,
                line: line
            )
        }
    }
}

@MainActor
private func findDescendantTextViews(in view: NSView) -> [NSTextView] {
    let matchingSubviewTextViews = view.subviews.flatMap(findDescendantTextViews(in:))
    if let textView = view as? NSTextView {
        return [textView] + matchingSubviewTextViews
    }
    return matchingSubviewTextViews
}

@MainActor
private func mountedTextViewIsVisible(_ textView: NSTextView) -> Bool {
    guard textView.window != nil, textView.isHidden == false else { return false }
    return effectiveMountedAlpha(of: textView) > 0.1
}

@MainActor
private func effectiveMountedAlpha(of view: NSView) -> CGFloat {
    var resolvedAlpha = view.alphaValue
    var currentAncestor = view.superview
    while let ancestor = currentAncestor {
        if ancestor.isHidden {
            return 0
        }
        resolvedAlpha *= ancestor.alphaValue
        currentAncestor = ancestor.superview
    }
    return resolvedAlpha
}
#endif
