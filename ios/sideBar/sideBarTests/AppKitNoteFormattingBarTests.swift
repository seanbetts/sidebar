#if os(macOS)
import AppKit
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class AppKitNoteFormattingBarTests: NotesDetailViewHostingTestCase {
    func testFormattingButtonOpensAnchoredPopoverOnMacOS() async throws {
        let harness = await MountedNotesDetailHarness()
        harness.mount()
        await harness.settle()

        harness.context.makeView().activateReadSurfaceEditing(at: .start)
        await waitUntil(timeout: .seconds(2)) {
            harness.context.editorViewModel.presentationMode == .edit
        }

        let button = try XCTUnwrap(findFormattingButton())
        button.performClick(nil)
        drainNotesHostingRunLoop()

        let popover = try XCTUnwrap(findFormattingPopover())
        let buttonFrame = button.convert(button.bounds, to: nil)
        let popoverFrame = popover.convert(popover.bounds, to: nil)

        XCTAssertGreaterThan(popoverFrame.width, buttonFrame.width)
        XCTAssertLessThan(abs(popoverFrame.maxX - buttonFrame.maxX), 160)
        harness.dispose()
    }

    func testClickOutsideFormattingPopoverDismissesItOnMacOS() async throws {
        let harness = await MountedNotesDetailHarness()
        harness.mount()
        await harness.settle()

        harness.context.makeView().activateReadSurfaceEditing(at: .start)
        await waitUntil(timeout: .seconds(2)) {
            harness.context.editorViewModel.presentationMode == .edit
        }

        let button = try XCTUnwrap(findFormattingButton())
        button.performClick(nil)
        drainNotesHostingRunLoop()

        XCTAssertNotNil(findFormattingPopover())

        let dismissBackdrop = try XCTUnwrap(findDismissBackdrop())
        dismissBackdrop.performClick(nil)
        drainNotesHostingRunLoop()

        XCTAssertNil(findFormattingPopover())
        harness.dispose()
    }
}

@MainActor
private func findFormattingButton() -> NSButton? {
    for window in NotesDetailViewTestRetainer.hostingWindows {
        guard let contentView = window.contentView else { continue }
        if let match = findDescendantView(in: contentView, identifier: "note-formatting-menu") as? NSButton {
            return match
        }
    }

    return nil
}

@MainActor
private func findFormattingPopover() -> NSView? {
    for window in NSApp.windows {
        guard let contentView = window.contentView else { continue }
        if let match = findDescendantView(in: contentView, identifier: "note-formatting-popover") {
            return match
        }
    }

    return nil
}

@MainActor
private func findDismissBackdrop() -> NSButton? {
    for window in NSApp.windows {
        guard let contentView = window.contentView else { continue }
        if let match = findDescendantView(in: contentView, identifier: "note-formatting-dismiss-backdrop") as? NSButton {
            return match
        }
    }

    return nil
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
