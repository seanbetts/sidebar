import Foundation
import SwiftUI
#if os(macOS)
import AppKit

@available(macOS 26.0, *)
extension AttributedNoteTextSurface {
    func synchronizeMacText(
        textView: NSTextView,
        isFocused: Bool,
        shouldForceStyleOnlySync: Bool
    ) -> (synchronizedTextLength: Int, textChanged: Bool) {
        let bridged = bridgeToNSAttributedString(text)
        let synchronizedTextLength = bridged.length
        let shouldSkipStyleOnlySync = preferPlainTextEditingStability &&
            isEditable &&
            isFocused &&
            !shouldForceStyleOnlySync &&
            textView.attributedString().string == bridged.string
        guard !textView.attributedString().isEqual(to: bridged), !shouldSkipStyleOnlySync else {
            return (synchronizedTextLength, false)
        }
        textView.textStorage?.setAttributedString(bridged)
        return (synchronizedTextLength, true)
    }

    func synchronizeMacSelection(
        textView: NSTextView,
        coordinator: Coordinator,
        synchronizedTextLength: Int,
        textChanged: Bool,
        preserveNativeSelection: Bool,
        isFocused: Bool
    ) {
        guard syncSelection else { return }
        let desiredRange = nsRange(from: selection, in: text)
        if preserveNativeSelection {
            let clamped = clampedRange(textView.selectedRange(), maxLength: synchronizedTextLength)
            if textView.selectedRange() != clamped {
                textView.setSelectedRange(clamped)
            }
            coordinator.preferNativeSelectionOnNextUpdate = false
            return
        }
        let shouldSyncSelection = !isEditable || !isFocused || textChanged
        if shouldSyncSelection && textView.selectedRange() != desiredRange {
            textView.setSelectedRange(desiredRange)
        }
    }

    func synchronizeMacTypingAttributes(textView: NSTextView) {
        guard syncSelection && isEditable else { return }
        let resolvedTypingAttributes = resolvedTypingAttributes(
            text: text,
            selectionTypingAttributes: selection.typingAttributes(in: text),
            fallbackTypingAttributes: fallbackTypingAttributes
        )
        let desiredTypingAttributes = typingAttributesDictionary(from: resolvedTypingAttributes)
        if !NSDictionary(dictionary: textView.typingAttributes).isEqual(to: desiredTypingAttributes) {
            textView.typingAttributes = desiredTypingAttributes
        }
    }
}
#endif
