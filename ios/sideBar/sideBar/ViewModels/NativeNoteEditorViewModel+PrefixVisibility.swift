@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeNoteEditorViewModel {
    enum PrefixRefreshScope {
        case full
        case lineSpan(ClosedRange<Int>?)
    }

    func updatePrefixVisibility() {
        guard !plainTextRuntimeModeEnabled else { return }
        refreshPrefixVisibility(scope: .full)
    }

    func requestPrefixRefresh(scope: PrefixRefreshScope) {
        guard !plainTextRuntimeModeEnabled else {
            pendingPrefixRefreshScope = nil
            prefixRefreshTask?.cancel()
            prefixRefreshTask = nil
            return
        }
        pendingPrefixRefreshScope = mergedPrefixScope(pendingPrefixRefreshScope, scope)
        guard prefixRefreshTask == nil else { return }
        prefixRefreshTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            let nextScope = self.pendingPrefixRefreshScope ?? .full
            self.pendingPrefixRefreshScope = nil
            self.prefixRefreshTask = nil
            self.refreshPrefixVisibility(scope: nextScope)
        }
    }

    func refreshPrefixVisibility(scope: PrefixRefreshScope) {
        guard !plainTextRuntimeModeEnabled else { return }
        let originalSnapshot = selectionSnapshot(in: attributedContent)
        var updated = attributedContent
        let useLegacyMarkerHeuristics = usesInjectedListMarkers
        let initialLines = lineInfos(in: updated)
        let requestedLineIndexes = requestedLineIndexes(for: scope, lineCount: initialLines.count)

        let listOrdinals = orderedListOrdinals(in: updated, lines: initialLines)
        var adjustedSnapshot = normalizeListMarkers(
            in: &updated,
            lines: initialLines,
            listOrdinals: listOrdinals,
            selection: originalSnapshot,
            lineIndexes: requestedLineIndexes
        )
        adjustedSnapshot = normalizeBlockquoteMarkers(
            in: &updated,
            lines: lineInfos(in: updated),
            selection: adjustedSnapshot,
            lineIndexes: requestedLineIndexes
        )

        let lines = lineInfos(in: updated)
        let activeLineIndexes = clampedLineIndexes(requestedLineIndexes, lineCount: lines.count)

        if shouldApplyTableLayout(
            in: updated,
            lines: lines,
            activeLineIndexes: activeLineIndexes
        ) {
            applyTableLayout(in: &updated, lines: lines)
        }
        applyCodeBlockSpacing(
            in: &updated,
            lines: lines,
            targetLineIndexes: activeLineIndexes
        )

        for (index, line) in lines.enumerated() {
            if let activeLineIndexes, !activeLineIndexes.contains(index) {
                continue
            }

            let lineStart = updated.index(updated.startIndex, offsetByCharacters: line.range.lowerBound)
            let lineEnd = updated.index(updated.startIndex, offsetByCharacters: line.range.upperBound)
            let lineRange = lineStart..<lineEnd
            let paragraphRange = lineRangeIncludingTrailingNewline(in: updated, lineRange: lineRange)
            let blockKind = resolvedBlockKind(
                in: &updated,
                lineRange: lineRange,
                lineText: line.text,
                allowInference: useLegacyMarkerHeuristics
            )
                ?? (line.text.isEmpty ? .blankLine : .paragraph)
            let previousParagraphSpacingAfter = previousParagraphSpacingAfter(
                in: updated,
                lineIndex: index,
                lines: lines,
                useLegacyMarkerHeuristics: useLegacyMarkerHeuristics
            )

            // Persist explicit editor blank lines so export can round-trip them as authored.
            if line.text.isEmpty, !paragraphRange.isEmpty {
                updated[paragraphRange].blockKind = .blankLine
            }

            let listDepth = updated[lineRange].listDepth
            if let baseStyle = paragraphStyle(for: blockKind, listDepth: listDepth) {
                let collapsedBefore = collapsedParagraphSpacingBefore(
                    originalBefore: baseStyle.paragraphSpacingBefore,
                    previousAfter: previousParagraphSpacingAfter
                )
                if collapsedBefore != baseStyle.paragraphSpacingBefore {
                    let mutable = baseStyle.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                    mutable.paragraphSpacingBefore = collapsedBefore
                    updated[paragraphRange].paragraphStyle = mutable
                } else {
                    updated[paragraphRange].paragraphStyle = baseStyle
                }
            }

            applyInlineIntentStyling(in: &updated, lineRange: lineRange, blockKind: blockKind)
        }

        guard updated != attributedContent else { return }

        isUpdatingPrefixVisibility = true
        attributedContent = updated
        let adjustedSelection = selection(from: adjustedSnapshot, in: updated)
        if selection != adjustedSelection { selection = adjustedSelection }
        isUpdatingPrefixVisibility = false
    }

    private func mergedPrefixScope(
        _ lhs: PrefixRefreshScope?,
        _ rhs: PrefixRefreshScope
    ) -> PrefixRefreshScope {
        guard let lhs else { return rhs }
        switch (lhs, rhs) {
        case (.full, _), (_, .full):
            return .full
        case let (.lineSpan(left), .lineSpan(right)):
            return .lineSpan(unionLineSpan(left, right))
        }
    }

    private func requestedLineIndexes(
        for scope: PrefixRefreshScope,
        lineCount: Int
    ) -> IndexSet? {
        switch scope {
        case .full:
            return nil
        case .lineSpan(let span):
            guard lineCount > 0 else { return IndexSet() }
            guard let span else { return IndexSet(integersIn: 0..<lineCount) }
            let lowerBound = max(0, span.lowerBound - 1)
            let upperBound = min(lineCount - 1, span.upperBound + 1)
            guard lowerBound <= upperBound else { return IndexSet() }
            return IndexSet(integersIn: lowerBound..<(upperBound + 1))
        }
    }

    private func clampedLineIndexes(
        _ lineIndexes: IndexSet?,
        lineCount: Int
    ) -> IndexSet? {
        guard let lineIndexes else { return nil }
        guard lineCount > 0 else { return IndexSet() }
        return lineIndexes.intersection(IndexSet(integersIn: 0..<lineCount))
    }

    private func shouldApplyTableLayout(
        in text: AttributedString,
        lines: [LineInfo],
        activeLineIndexes: IndexSet?
    ) -> Bool {
        guard let activeLineIndexes else { return true }
        for lineIndex in activeLineIndexes {
            guard lineIndex >= 0, lineIndex < lines.count else { continue }
            let line = lines[lineIndex]
            let lineRange = attributedRange(for: line.range, in: text)
            if tableRowInfo(in: text, range: lineRange) != nil {
                return true
            }
        }
        return false
    }

    private func previousParagraphSpacingAfter(
        in text: AttributedString,
        lineIndex: Int,
        lines: [LineInfo],
        useLegacyMarkerHeuristics: Bool
    ) -> CGFloat {
        guard lineIndex > 0 else { return 0 }
        let previous = lines[lineIndex - 1]
        let prevStart = text.index(text.startIndex, offsetByCharacters: previous.range.lowerBound)
        let prevEnd = text.index(text.startIndex, offsetByCharacters: previous.range.upperBound)
        let prevRange = prevStart..<prevEnd
        let prevKind: BlockKind = {
            if useLegacyMarkerHeuristics {
                return text.blockKind(in: prevRange)
                    ?? inferredBlockKind(from: previous.text)
                    ?? (previous.text.isEmpty ? .blankLine : .paragraph)
            }
            return text.blockKind(in: prevRange) ?? (previous.text.isEmpty ? .blankLine : .paragraph)
        }()
        let prevDepth = text[prevRange].listDepth
        return paragraphStyle(for: prevKind, listDepth: prevDepth)?.paragraphSpacing ?? 0
    }

    func applyCodeBlockSpacing(
        in text: inout AttributedString,
        lines: [LineInfo],
        targetLineIndexes: IndexSet? = nil
    ) {
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let lineStart = text.index(text.startIndex, offsetByCharacters: line.range.lowerBound)
            let lineEnd = text.index(text.startIndex, offsetByCharacters: line.range.upperBound)
            let lineRange = lineStart..<lineEnd
            let blockKind = text.blockKind(in: lineRange) ?? inferredBlockKind(from: line.text)

            guard blockKind == .codeBlock else {
                index += 1
                continue
            }

            var endIndex = index
            while endIndex + 1 < lines.count {
                let next = lines[endIndex + 1]
                let nextStart = text.index(text.startIndex, offsetByCharacters: next.range.lowerBound)
                let nextEnd = text.index(text.startIndex, offsetByCharacters: next.range.upperBound)
                let nextRange = nextStart..<nextEnd
                let nextKind = text.blockKind(in: nextRange) ?? inferredBlockKind(from: next.text)
                if nextKind == .codeBlock {
                    endIndex += 1
                } else {
                    break
                }
            }

            if shouldStyleCodeBlock(
                startIndex: index,
                endIndex: endIndex,
                targetLineIndexes: targetLineIndexes
            ) {
                for lineIndex in index...endIndex {
                    let info = lines[lineIndex]
                    let start = text.index(text.startIndex, offsetByCharacters: info.range.lowerBound)
                    let end = text.index(text.startIndex, offsetByCharacters: info.range.upperBound)
                    let range = lineRangeIncludingTrailingNewline(in: text, lineRange: start..<end)
                    let isFirst = lineIndex == index
                    let isLast = lineIndex == endIndex
                    let style = paragraphStyle(
                        lineSpacing: em(0.5, fontSize: inlineCodeFontSize),
                        spacingBefore: isFirst ? rem(1) : 0,
                        spacingAfter: isLast ? rem(1) : 0,
                        headIndent: DesignTokens.Spacing.md,
                        tailIndent: DesignTokens.Spacing.md
                    )
                    text[range].paragraphStyle = style
                }
            }

            index = endIndex + 1
        }
    }

    private func shouldStyleCodeBlock(
        startIndex: Int,
        endIndex: Int,
        targetLineIndexes: IndexSet?
    ) -> Bool {
        guard let targetLineIndexes else { return true }
        let blockIndexes = IndexSet(integersIn: startIndex..<(endIndex + 1))
        return !targetLineIndexes.isDisjoint(with: blockIndexes)
    }

    func lineRangeIncludingTrailingNewline(
        in text: AttributedString,
        lineRange: Range<AttributedString.Index>
    ) -> Range<AttributedString.Index> {
        var upper = lineRange.upperBound
        if upper < text.endIndex, text.characters[upper].isNewline {
            upper = text.index(afterCharacter: upper)
        }
        return lineRange.lowerBound..<upper
    }

    func resolvedBlockKind(
        in text: inout AttributedString,
        lineRange: Range<AttributedString.Index>,
        lineText: String,
        allowInference: Bool
    ) -> BlockKind? {
        let explicitBlockKind = text.blockKind(in: lineRange)
        guard allowInference else {
            return explicitBlockKind
        }

        let inferred = inferredBlockKind(from: lineText)
        let blockKind = explicitBlockKind ?? inferred
        if blockKind == .horizontalRule, explicitBlockKind == nil {
            text[lineRange].blockKind = .horizontalRule
            if let paragraphStyle = paragraphStyle(for: .horizontalRule) {
                text[lineRange].paragraphStyle = paragraphStyle
            }
        }
        return blockKind
    }

    func attributedRange(for range: Range<Int>, in text: AttributedString) -> Range<AttributedString.Index> {
        let start = text.index(text.startIndex, offsetByCharacters: range.lowerBound)
        let end = text.index(text.startIndex, offsetByCharacters: range.upperBound)
        return start..<end
    }

    func lineRanges(in text: AttributedString) -> [Range<AttributedString.Index>] {
        var lines: [Range<AttributedString.Index>] = []
        var start = text.startIndex
        var current = text.startIndex

        while current < text.endIndex {
            if text.characters[current].isNewline {
                lines.append(start..<current)
                start = text.index(afterCharacter: current)
                current = start
            } else {
                current = text.index(afterCharacter: current)
            }
        }

        if start <= text.endIndex {
            lines.append(start..<text.endIndex)
        }

        return lines
    }

    func selectionLineSpan(in text: AttributedString) -> ClosedRange<Int>? {
        let ranges = lineRanges(in: text)
        var coveredLineIndexes = IndexSet()

        func includeLines(containing index: AttributedString.Index) {
            for (lineIndex, range) in ranges.enumerated() {
                if range.contains(index) || index == range.upperBound {
                    coveredLineIndexes.insert(lineIndex)
                    return
                }
            }
        }

        switch selection.indices(in: text) {
        case .insertionPoint(let index):
            includeLines(containing: index)
        case .ranges(let selectedRanges):
            for selectedRange in selectedRanges.ranges {
                if selectedRange.isEmpty {
                    includeLines(containing: selectedRange.lowerBound)
                } else {
                    for (lineIndex, lineRange) in ranges.enumerated() where lineRange.overlaps(selectedRange) {
                        coveredLineIndexes.insert(lineIndex)
                    }
                }
            }
        }

        guard let lower = coveredLineIndexes.first,
              let upper = coveredLineIndexes.last else { return nil }
        return lower...upper
    }
}
