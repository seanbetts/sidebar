@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeNoteEditorViewModel {
    struct InlineFormattingState: Equatable {
        var bold: Bool = false
        var italic: Bool = false
        var underline: Bool = false

        static let plain = InlineFormattingState()

        func contains(_ formatting: NoteFormatting) -> Bool {
            switch formatting {
            case .bold:
                return bold
            case .italic:
                return italic
            case .underline:
                return underline
            }
        }

        mutating func set(_ formatting: NoteFormatting, enabled: Bool) {
            switch formatting {
            case .bold:
                bold = enabled
            case .italic:
                italic = enabled
            case .underline:
                underline = enabled
            }
        }
    }

    func constrainedEditorDocument(from source: AttributedString) -> AttributedString {
        var normalized = source
        constrainEditorDocument(&normalized)
        return normalized
    }

    func constrainEditorDocument(_ text: inout AttributedString) {
        NoteTextFormattingDefinition(baseFontSize: baseFontSize).constrainDocument(&text)
    }

    func isFormattingActive(_ formatting: NoteFormatting) -> Bool {
        let nonEmptyRanges = selectionRanges().ranges.filter { !$0.isEmpty }
        guard !nonEmptyRanges.isEmpty else {
            let typingState = inlineFormattingState(
                from: selection.typingAttributes(in: attributedContent)
            )
            if typingState.contains(formatting) {
                return true
            }
            return inheritedFormattingStateAtInsertionPoint().contains(formatting)
        }

        return nonEmptyRanges.allSatisfy { range in
            rangeHasFormatting(range, formatting: formatting)
        }
    }

    func setFormatting(_ formatting: NoteFormatting, enabled: Bool) {
        guard !isReadOnly else { return }
        applyFormattingMutation(formatting, enabled: enabled)
    }

    func toggleFormatting(_ formatting: NoteFormatting) {
        let nonEmptyRanges = selectionRanges().ranges.filter { !$0.isEmpty }
        guard !nonEmptyRanges.isEmpty else {
            let enabled = !inlineFormattingState(
                from: selection.typingAttributes(in: attributedContent)
            ).contains(formatting)
            applyFormattingMutation(formatting, enabled: enabled)
            return
        }

        let shouldEnable = nonEmptyRanges.contains { range in
            !rangeHasFormatting(range, formatting: formatting)
        }
        applyFormattingMutation(formatting, enabled: shouldEnable)
    }

    private func applyFormattingMutation(
        _ formatting: NoteFormatting,
        enabled: Bool
    ) {
        let nonEmptyRanges = selectionRanges().ranges.filter { !$0.isEmpty }
        guard !nonEmptyRanges.isEmpty else {
            transformSelectionAttributes { attrs in
                var state = inlineFormattingState(from: attrs)
                state.set(formatting, enabled: enabled)
                applyInlineFormattingState(state, to: &attrs)
                attrs.paragraphStyle = NoteTextParagraphMetrics.bodyParagraphStyle(
                    baseFontSize: baseFontSize
                )
            }
            return
        }

        let selectionSnapshot = selectionSnapshot(in: attributedContent)
        var updatedSelection = selection
        attributedContent.transformAttributes(in: &updatedSelection) { attrs in
            var state = inlineFormattingState(from: attrs)
            state.set(formatting, enabled: enabled)
            applyInlineFormattingState(state, to: &attrs)
            attrs.paragraphStyle = NoteTextParagraphMetrics.bodyParagraphStyle(
                baseFontSize: baseFontSize
            )
        }
        selection = selection(from: selectionSnapshot, in: attributedContent)
    }

    private func rangeHasFormatting(
        _ range: Range<AttributedString.Index>,
        formatting: NoteFormatting
    ) -> Bool {
        let runSnapshots = formattingRunSnapshots(in: attributedContent, within: range)
        guard !runSnapshots.isEmpty else { return false }
        return runSnapshots.allSatisfy { $0.state.contains(formatting) }
    }

    private func inheritedFormattingStateAtInsertionPoint() -> InlineFormattingState {
        let insertionIndex: AttributedString.Index?
        switch selection.indices(in: attributedContent) {
        case .insertionPoint(let index):
            insertionIndex = index
        case .ranges(let ranges):
            insertionIndex = ranges.ranges.first?.lowerBound
        }

        guard let insertionIndex,
              insertionIndex > attributedContent.startIndex else {
            return .plain
        }

        let previousIndex = attributedContent.index(beforeCharacter: insertionIndex)
        let previousRange = previousIndex..<insertionIndex
        let runSnapshots = formattingRunSnapshots(in: attributedContent, within: previousRange)
        return runSnapshots.first?.state ?? .plain
    }

    private func formattingRunSnapshots(in text: AttributedString) -> [FormattingRunSnapshot] {
        text.runs.compactMap { run in
            snapshot(for: run, in: text)
        }
    }

    private func formattingRunSnapshots(
        in text: AttributedString,
        within range: Range<AttributedString.Index>
    ) -> [FormattingRunSnapshot] {
        text[range].runs.compactMap { run in
            snapshot(for: run, in: text)
        }
    }

    private func snapshot(
        for run: AttributedString.Runs.Run,
        in text: AttributedString
    ) -> FormattingRunSnapshot? {
        guard !run.range.isEmpty else { return nil }
        let lower = text.characters.distance(from: text.startIndex, to: run.range.lowerBound)
        let upper = text.characters.distance(from: text.startIndex, to: run.range.upperBound)
        return FormattingRunSnapshot(
            range: lower..<upper,
            state: inlineFormattingState(from: run)
        )
    }

    private struct FormattingRunSnapshot {
        let range: Range<Int>
        let state: InlineFormattingState
    }
}
