#if os(macOS)
import AppKit
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class AppKitNoteFormattingBarTests: NotesDetailViewHostingTestCase {
    func testFormattingButtonOpensAnchoredPopoverOnMacOS() async throws {
        let harness = await MountedNotesDetailHarness()
        defer { harness.dispose() }
        harness.mount()
        await harness.settle()

        harness.context.makeView().activateReadSurfaceEditing(at: .start)
        await waitUntil(timeout: .seconds(2)) {
            harness.context.editorViewModel.presentationMode == .edit
        }

        let button = try await waitForFormattingButton()
        button.performClick(nil)
        _ = await waitUntil(timeout: .seconds(2)) {
            findFormattingPopover() != nil
        }

        let popover = try XCTUnwrap(findFormattingPopover())
        let buttonFrame = button.convert(button.bounds, to: nil)
        let popoverFrame = popover.convert(popover.bounds, to: nil)

        XCTAssertGreaterThan(popoverFrame.width, buttonFrame.width)
        XCTAssertLessThan(abs(popoverFrame.maxX - buttonFrame.maxX), 160)
    }

    func testFormattingPopoverMatchesIOSSectionStructureOnMacOS() async throws {
        let harness = await MountedNotesDetailHarness()
        defer { harness.dispose() }
        harness.mount()
        await harness.settle()

        harness.context.makeView().activateReadSurfaceEditing(at: .start)
        await waitUntil(timeout: .seconds(2)) {
            harness.context.editorViewModel.presentationMode == .edit
        }

        try await openFormattingPopover()

        let popover = try XCTUnwrap(findFormattingPopover())
        XCTAssertNotNil(findDescendantView(in: popover, identifier: "note-formatting-text-style-strip"))
        XCTAssertNotNil(findDescendantView(in: popover, identifier: "note-formatting-inline-group"))
        XCTAssertNotNil(findDescendantView(in: popover, identifier: "note-formatting-code-group"))
        XCTAssertNotNil(findDescendantView(in: popover, identifier: "note-formatting-link-group"))
        XCTAssertNotNil(findDescendantView(in: popover, identifier: "note-formatting-future-list-group"))
        XCTAssertNotNil(findDescendantView(in: popover, identifier: "note-formatting-future-blockquote-group"))
        XCTAssertEqual(findTextStyleButtonIdentifiers(in: popover), [
            "note-formatting-text-style-title",
            "note-formatting-text-style-heading",
            "note-formatting-text-style-subheading",
            "note-formatting-text-style-body"
        ])
        XCTAssertEqual(findTextStyleButtonTitles(in: popover), ["Title", "Heading", "Subhead", "Body"])
    }

    func testFormattingActionDismissesPopoverOnMacOS() async throws {
        let harness = await MountedNotesDetailHarness()
        defer { harness.dispose() }
        harness.mount()
        await harness.settle()

        harness.context.makeView().activateReadSurfaceEditing(at: .start)
        await waitUntil(timeout: .seconds(2)) {
            harness.context.editorViewModel.presentationMode == .edit
        }

        try await openFormattingPopover()

        let boldButton = try XCTUnwrap(findActionButton(identifier: "note-formatting-bold"))
        boldButton.performClick(nil)
        drainNotesHostingRunLoop()

        XCTAssertNil(findFormattingPopover())
    }

    func testFormattingPopoverCoversTriggerButtonFootprintOnMacOS() async throws {
        let harness = await MountedNotesDetailHarness()
        defer { harness.dispose() }
        harness.mount()
        await harness.settle()

        harness.context.makeView().activateReadSurfaceEditing(at: .start)
        await waitUntil(timeout: .seconds(2)) {
            harness.context.editorViewModel.presentationMode == .edit
        }

        let button = try await waitForFormattingButton()
        button.performClick(nil)
        _ = await waitUntil(timeout: .seconds(2)) {
            findFormattingPopover() != nil
        }

        let popover = try XCTUnwrap(findFormattingPopover())
        let buttonFrame = button.convert(button.bounds, to: nil)
        let popoverFrame = popover.convert(popover.bounds, to: nil)

        XCTAssertTrue(popoverFrame.contains(buttonFrame))
    }

    func testClickOutsideFormattingPopoverDismissesItOnMacOS() async throws {
        let harness = await MountedNotesDetailHarness()
        defer { harness.dispose() }
        harness.mount()
        await harness.settle()

        harness.context.makeView().activateReadSurfaceEditing(at: .start)
        await waitUntil(timeout: .seconds(2)) {
            harness.context.editorViewModel.presentationMode == .edit
        }

        let button = try await waitForFormattingButton()
        button.performClick(nil)
        _ = await waitUntil(timeout: .seconds(2)) {
            findFormattingPopover() != nil
        }

        XCTAssertNotNil(findFormattingPopover())

        let dismissBackdrop = try XCTUnwrap(findDismissBackdrop())
        dismissBackdrop.performClick(nil)
        drainNotesHostingRunLoop()

        XCTAssertNil(findFormattingPopover())
    }

    func testFormattingPopoverUsesAppKitOverlayHostOutsideSwiftUIContentViewOnMacOS() async throws {
        let harness = await MountedNotesDetailHarness()
        defer { harness.dispose() }
        harness.mount()
        await harness.settle()

        harness.context.makeView().activateReadSurfaceEditing(at: .start)
        await waitUntil(timeout: .seconds(2)) {
            harness.context.editorViewModel.presentationMode == .edit
        }

        try await openFormattingPopover()

        let popover = try XCTUnwrap(findFormattingPopover())
        let dismissBackdrop = try XCTUnwrap(findDismissBackdrop())
        let contentView = try XCTUnwrap(popover.window?.contentView)

        XCTAssertFalse(popover.superview === contentView)
        XCTAssertFalse(dismissBackdrop.superview === contentView)
    }

    private func openFormattingPopover() async throws {
        let button = try await waitForFormattingButton()
        button.performClick(nil)
        _ = await waitUntil(timeout: .seconds(2)) {
            findFormattingPopover() != nil
        }
        XCTAssertNotNil(findFormattingPopover())
    }

    private func waitForFormattingButton() async throws -> NSButton {
        _ = await waitUntil(timeout: .seconds(2)) {
            guard let button = findFormattingButton() else {
                return false
            }
            return button.isEnabled
        }
        return try XCTUnwrap(findFormattingButton())
    }
}

@MainActor
private func findFormattingButton() -> NSButton? {
    layoutMountedNoteWindows()
    for window in NotesDetailViewTestRetainer.hostingWindows.reversed() {
        guard let contentView = window.contentView else { continue }
        if let match = findDescendantView(in: contentView, identifier: "note-formatting-menu") as? NSButton {
            return match
        }
    }

    return nil
}

@MainActor
private func findFormattingPopover() -> NSView? {
    layoutMountedNoteWindows()
    for window in NotesDetailViewTestRetainer.hostingWindows.reversed() {
        for rootView in overlaySearchRoots(for: window) {
            if let match = findDescendantView(in: rootView, identifier: "note-formatting-popover"),
               !match.isHidden {
                return match
            }
        }
    }

    return nil
}

@MainActor
private func findDismissBackdrop() -> NSButton? {
    layoutMountedNoteWindows()
    for window in NotesDetailViewTestRetainer.hostingWindows.reversed() {
        for rootView in overlaySearchRoots(for: window) {
            if let match = findDescendantView(in: rootView, identifier: "note-formatting-dismiss-backdrop") as? NSButton,
               !match.isHidden {
                return match
            }
        }
    }

    return nil
}

@MainActor
private func overlaySearchRoots(for window: NSWindow) -> [NSView] {
    var roots: [NSView] = []
    if let contentSuperview = window.contentView?.superview {
        roots.append(contentSuperview)
    }
    if let contentView = window.contentView {
        roots.append(contentView)
    }
    return roots
}

@MainActor
private func layoutMountedNoteWindows() {
    for window in NotesDetailViewTestRetainer.hostingWindows {
        window.contentViewController?.view.layoutSubtreeIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
    }
    drainNotesHostingRunLoop()
}

@MainActor
private func findActionButton(identifier: String) -> NSButton? {
    guard let popover = findFormattingPopover() else {
        return nil
    }

    return findDescendantView(in: popover, identifier: identifier) as? NSButton
}

@MainActor
private func findTextStyleButtonIdentifiers(in popover: NSView) -> [String] {
    guard let strip = findDescendantView(in: popover, identifier: "note-formatting-text-style-buttons") else {
        return []
    }

    return strip.subviews.compactMap { $0.identifier?.rawValue }
}

@MainActor
private func findTextStyleButtonTitles(in popover: NSView) -> [String] {
    guard let strip = findDescendantView(in: popover, identifier: "note-formatting-text-style-buttons") else {
        return []
    }

    return strip.subviews.compactMap { ($0 as? NSButton)?.title }
}

@MainActor
private func findDescendantView(
    in view: NSView,
    identifier: String
) -> NSView? {
    if view.identifier?.rawValue == identifier {
        return view
    }

    for subview in view.subviews {
        if let match = findDescendantView(in: subview, identifier: identifier) {
            return match
        }
    }

    return nil
}
#endif
