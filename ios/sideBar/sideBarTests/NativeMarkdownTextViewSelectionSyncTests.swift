import Foundation
import SwiftUI
import XCTest
@testable import sideBar

#if os(iOS)
@MainActor
@available(iOS 26.0, *)
final class NativeMarkdownTextViewSelectionSyncTests: XCTestCase {
    private func makeCoordinator() -> NativeMarkdownTextView.Coordinator {
        let view = NativeMarkdownTextView(
            text: .constant(AttributedString("Hello")),
            selection: .constant(AttributedTextSelection())
        )
        return view.makeCoordinator()
    }

    func testShouldApplyDesiredSelectionReturnsFalseForMatchingRange() {
        let coordinator = makeCoordinator()

        let shouldApply = coordinator.shouldApplyDesiredSelection(
            desiredRange: NSRange(location: 3, length: 0),
            currentRange: NSRange(location: 3, length: 0),
            isFirstResponder: true,
            didReplaceText: false
        )

        XCTAssertFalse(shouldApply)
    }

    func testShouldApplyDesiredSelectionSkipsStaleSelectionWhileFocused() {
        let coordinator = makeCoordinator()
        coordinator.lastSelectionReportedByUIKit = NSRange(location: 2, length: 0)

        let shouldApply = coordinator.shouldApplyDesiredSelection(
            desiredRange: NSRange(location: 2, length: 0),
            currentRange: NSRange(location: 4, length: 0),
            isFirstResponder: true,
            didReplaceText: false
        )

        XCTAssertFalse(shouldApply)
    }

    func testShouldApplyDesiredSelectionSkipsExternalSelectionWhileFocused() {
        let coordinator = makeCoordinator()
        coordinator.lastSelectionReportedByUIKit = NSRange(location: 2, length: 0)

        let shouldApply = coordinator.shouldApplyDesiredSelection(
            desiredRange: NSRange(location: 1, length: 2),
            currentRange: NSRange(location: 4, length: 0),
            isFirstResponder: true,
            didReplaceText: false
        )

        XCTAssertFalse(shouldApply)
    }

    func testShouldApplyDesiredSelectionAppliesWhenNotFocused() {
        let coordinator = makeCoordinator()
        coordinator.lastSelectionReportedByUIKit = NSRange(location: 2, length: 0)

        let shouldApply = coordinator.shouldApplyDesiredSelection(
            desiredRange: NSRange(location: 2, length: 0),
            currentRange: NSRange(location: 0, length: 0),
            isFirstResponder: false,
            didReplaceText: false
        )

        XCTAssertTrue(shouldApply)
    }

    func testShouldApplyDesiredSelectionRestoresUIKitSelectionAfterTextReplacement() {
        let coordinator = makeCoordinator()
        coordinator.lastSelectionReportedByUIKit = NSRange(location: 2, length: 0)

        let shouldApply = coordinator.shouldApplyDesiredSelection(
            desiredRange: NSRange(location: 2, length: 0),
            currentRange: NSRange(location: 0, length: 0),
            isFirstResponder: true,
            didReplaceText: true
        )

        XCTAssertTrue(shouldApply)
    }

    func testShouldApplyDesiredSelectionSkipsMismatchedSelectionAfterTextReplacement() {
        let coordinator = makeCoordinator()
        coordinator.lastSelectionReportedByUIKit = NSRange(location: 2, length: 0)

        let shouldApply = coordinator.shouldApplyDesiredSelection(
            desiredRange: NSRange(location: 3, length: 0),
            currentRange: NSRange(location: 0, length: 0),
            isFirstResponder: true,
            didReplaceText: true
        )

        XCTAssertFalse(shouldApply)
    }
}
#endif
