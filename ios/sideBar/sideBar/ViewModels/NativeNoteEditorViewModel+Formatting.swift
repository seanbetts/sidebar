@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeNoteEditorViewModel {
    func toggleInlineIntent(_ intent: InlinePresentationIntent) {
        let nonEmptyRanges = selectionRanges().ranges.filter { !$0.isEmpty }
        guard !nonEmptyRanges.isEmpty else {
            let enabled = !typingAttributesHaveInlineIntentOrTrait(
                selection.typingAttributes(in: attributedContent),
                intent: intent
            )
            applyInlineIntent(intent, enabled: enabled)
            return
        }

        let shouldEnable = nonEmptyRanges.contains { range in
            !rangeHasInlineIntentOrTrait(range, intent: intent)
        }
        for range in nonEmptyRanges {
            applyInlineIntentToRange(intent, enabled: shouldEnable, range: range)
        }
    }

    func stripUnsupportedInlineStyles(in text: inout AttributedString) {
        for run in text.runs {
            let range = run.range
            var intents = text[range].inlinePresentationIntent ?? []
            intents.remove(.code)
            text[range].inlinePresentationIntent = intents.isEmpty ? nil : intents
            text[range].strikethroughStyle = nil
        }
    }
}
