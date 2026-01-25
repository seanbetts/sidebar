@preconcurrency import Foundation
import Combine
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
public final class NativeMarkdownEditorViewModel: ObservableObject {
    @Published public var attributedContent: AttributedString = AttributedString()
    @Published public var selection: AttributedTextSelection = AttributedTextSelection()
    @Published public var isReadOnly: Bool = false {
        didSet {
            guard isReadOnly != oldValue else { return }
            updatePrefixVisibility()
        }
    }
    @Published public private(set) var hasUnsavedChanges: Bool = false

    private let importer = MarkdownImporter()
    private let exporter = MarkdownExporter()
    private let baseFontSize: CGFloat = 16
    private let inlineCodeFontSize: CGFloat = 14
    private let heading1FontSize: CGFloat = 32
    private let heading2FontSize: CGFloat = 24
    private let heading3FontSize: CGFloat = 20
    private let heading4FontSize: CGFloat = 18
    private let heading5FontSize: CGFloat = 17
    private let heading6FontSize: CGFloat = 16
    private let bodyFont = Font.system(size: 16)
    private let inlineCodeFont = Font.system(size: 14, weight: .regular, design: .monospaced)
    private let blockCodeFont = Font.system(size: 14, weight: .regular, design: .monospaced)
    private let style = SideBarMarkdownStyle.default
    private var frontmatter: String?
    private var lastSavedContent: String = ""
    private var autosaveTask: Task<Void, Never>?
    private var isApplyingShortcut = false
    private var isUpdatingPrefixVisibility = false
    private var lastSelectionLineIndex: Int?
    private static let headingRegex = try? NSRegularExpression(pattern: #"^#{1,6}\s"#)
    private static let bulletRegex = try? NSRegularExpression(pattern: #"^\s*[-+*]\s"#)
    private static let orderedRegex = try? NSRegularExpression(pattern: #"^\s*\d+\.\s"#)
    private static let taskRegex = try? NSRegularExpression(pattern: #"^\s*[-+*]\s+\[[ xX]\]\s"#)
    private static let quoteRegex = try? NSRegularExpression(pattern: #"^\s*>\s"#)

    public init() {}

    public func loadMarkdown(_ markdown: String) {
        let result = importer.attributedString(from: markdown)
        frontmatter = result.frontmatter
        attributedContent = result.attributedString
        selection = AttributedTextSelection()
        lastSavedContent = markdown
        hasUnsavedChanges = false
    }

    public func currentMarkdown() -> String {
        exporter.markdown(from: attributedContent, frontmatter: frontmatter)
    }

    public func markSaved(markdown: String) {
        lastSavedContent = markdown
        hasUnsavedChanges = false
    }

    public func isBoldActive() -> Bool {
        hasInlineIntent(.stronglyEmphasized)
    }

    public func setBold(_ enabled: Bool) {
        applyInlineIntent(.stronglyEmphasized, enabled: enabled)
    }

    public func isItalicActive() -> Bool {
        hasInlineIntent(.emphasized)
    }

    public func setItalic(_ enabled: Bool) {
        applyInlineIntent(.emphasized, enabled: enabled)
    }

    public func toggleInlineCode() {
        let enabled = !hasInlineIntent(.code)
        applyInlineIntent(.code, enabled: enabled)
    }

    public func applyLink(_ url: URL) {
        attributedContent.transformAttributes(in: &selection) { attrs in
            attrs.link = url
            attrs.foregroundColor = .accentColor
            attrs.underlineStyle = .single
        }
    }

    public func applyHeading(level: Int) {
        setBlockKind(headingKind(for: level))
    }

    public func applyList(ordered: Bool) {
        setBlockKind(ordered ? .orderedList : .bulletList, listDepth: 1)
    }

    public func applyTask() {
        setBlockKind(.taskUnchecked, listDepth: 1)
    }

    public func applyQuote() {
        setBlockKind(.blockquote)
    }

    public func applyCodeBlock(language: String?) {
        _ = language
        setBlockKind(.codeBlock)
    }

    // swiftlint:disable cyclomatic_complexity
    public func applyFormatting(_ formatting: MarkdownFormatting) {
        guard !isReadOnly else { return }

        switch formatting {
        case .bold:
            toggleInlineIntent(.stronglyEmphasized)
        case .italic:
            toggleInlineIntent(.emphasized)
        case .inlineCode:
            toggleInlineIntent(.code)
        case .strikethrough:
            toggleStrikethrough()
        case .heading(let level):
            setBlockKind(headingKind(for: level))
        case .bulletList:
            setBlockKind(.bulletList, listDepth: 1)
        case .orderedList:
            setBlockKind(.orderedList, listDepth: 1)
        case .taskList:
            setBlockKind(.taskUnchecked, listDepth: 1)
        case .blockquote:
            setBlockKind(.blockquote)
        case .codeBlock:
            setBlockKind(.codeBlock)
        case .link(let url):
            insertLink(url)
        case .horizontalRule:
            insertHorizontalRule()
        }
    }
    // swiftlint:enable cyclomatic_complexity

    public func handleContentChange(previous: AttributedString) {
        if isUpdatingPrefixVisibility {
            isUpdatingPrefixVisibility = false
            return
        }

        guard !isReadOnly, !isApplyingShortcut else {
            return
        }

        let insertedCharacter = lastInsertedCharacter(previous: previous, current: attributedContent)
        var updated = attributedContent

        if let newSelection = MarkdownShortcutProcessor.processShortcuts(
            in: &updated,
            selection: selection,
            lastInsertedCharacter: insertedCharacter
        ) {
            isApplyingShortcut = true
            attributedContent = updated
            selection = newSelection
            isApplyingShortcut = false
        }

        scheduleAutosave()
        lastSelectionLineIndex = lineIndexForSelection(in: attributedContent)
        updatePrefixVisibility()
    }

    public func handleSelectionChange() {
        guard !isReadOnly, !isUpdatingPrefixVisibility else { return }
        let currentLineIndex = lineIndexForSelection(in: attributedContent)
        if currentLineIndex == lastSelectionLineIndex {
            return
        }
        lastSelectionLineIndex = currentLineIndex
        updatePrefixVisibility()
    }

    private func toggleInlineIntent(_ intent: InlinePresentationIntent) {
        let ranges = selectionRanges()
        for range in ranges.ranges where !range.isEmpty {
            let current = attributedContent[range].inlinePresentationIntent ?? []
            let enabled = !current.contains(intent)
            applyInlineIntent(intent, enabled: enabled, range: range)
        }
    }

    private func toggleStrikethrough() {
        let ranges = selectionRanges()
        for range in ranges.ranges where !range.isEmpty {
            if attributedContent[range].strikethroughStyle == nil {
                attributedContent[range].strikethroughStyle = .single
                attributedContent[range].foregroundColor = DesignTokens.Colors.textSecondary
            } else {
                attributedContent[range].strikethroughStyle = nil
                let blockKind = attributedContent.blockKind(in: range)
                attributedContent[range].foregroundColor = baseForegroundColor(for: blockKind)
            }
        }
    }

    private func setBlockKind(_ blockKind: BlockKind, listDepth: Int? = nil) {
        let ranges = selectionRanges()
        for range in ranges.ranges {
            let paragraphRange = findParagraphRange(containing: range)
            attributedContent[paragraphRange].blockKind = blockKind
            if let listDepth {
                attributedContent[paragraphRange].listDepth = listDepth
            } else {
                attributedContent[paragraphRange].listDepth = nil
            }
            applyBlockStyle(blockKind: blockKind, range: paragraphRange)
            applyPresentationIntent(blockKind: blockKind, listDepth: listDepth, range: paragraphRange)
        }
    }

    private func findParagraphRange(containing range: Range<AttributedString.Index>) -> Range<AttributedString.Index> {
        var start = range.lowerBound
        var end = range.upperBound

        while start > attributedContent.startIndex {
            let prev = attributedContent.index(beforeCharacter: start)
            if attributedContent.characters[prev] == "\n" {
                break
            }
            start = prev
        }

        while end < attributedContent.endIndex {
            if attributedContent.characters[end] == "\n" {
                break
            }
            end = attributedContent.index(afterCharacter: end)
        }

        return start..<end
    }

    private func insertLink(_ url: URL) {
        let ranges = selectionRanges()
        guard let range = ranges.ranges.first else { return }

        if range.isEmpty {
            let placeholder = AttributedString("link")
            var insert = placeholder
            insert[insert.startIndex..<insert.endIndex].link = url
            attributedContent.insert(insert, at: range.lowerBound)
            let cursorIndex = attributedContent.index(range.lowerBound, offsetByCharacters: placeholder.characters.count)
            selection = AttributedTextSelection(range: cursorIndex..<cursorIndex)
        } else {
            attributedContent[range].link = url
            attributedContent[range].foregroundColor = .accentColor
            attributedContent[range].underlineStyle = .single
        }
    }

    private func insertHorizontalRule() {
        var hr = AttributedString("---")
        let range = hr.startIndex..<hr.endIndex
        hr[range].blockKind = .horizontalRule
        hr[range].foregroundColor = DesignTokens.Colors.border

        let insertIndex = selectionRanges().ranges.first?.lowerBound ?? attributedContent.endIndex
        attributedContent.insert(hr, at: insertIndex)
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self else { return }
            let current = self.currentMarkdown()
            self.hasUnsavedChanges = current != self.lastSavedContent
        }
    }

    private func lastInsertedCharacter(previous: AttributedString, current: AttributedString) -> Character? {
        let prev = String(previous.characters)
        let curr = String(current.characters)
        guard curr.count == prev.count + 1 else { return nil }

        var prevIndex = prev.startIndex
        var currIndex = curr.startIndex

        while prevIndex < prev.endIndex && currIndex < curr.endIndex {
            if prev[prevIndex] != curr[currIndex] {
                return curr[currIndex]
            }
            prevIndex = prev.index(after: prevIndex)
            currIndex = curr.index(after: currIndex)
        }

        if currIndex < curr.endIndex {
            return curr[currIndex]
        }

        return nil
    }

    private func headingKind(for level: Int) -> BlockKind {
        switch level {
        case 1: return .heading1
        case 2: return .heading2
        case 3: return .heading3
        case 4: return .heading4
        case 5: return .heading5
        default: return .heading6
        }
    }

    private func baseFont(for blockKind: BlockKind?) -> Font {
        switch blockKind {
        case .heading1:
            return .system(size: heading1FontSize, weight: .bold)
        case .heading2:
            return .system(size: heading2FontSize, weight: .semibold)
        case .heading3:
            return .system(size: heading3FontSize, weight: .semibold)
        case .heading4:
            return .system(size: heading4FontSize, weight: .semibold)
        case .heading5:
            return .system(size: heading5FontSize, weight: .semibold)
        case .heading6:
            return .system(size: heading6FontSize, weight: .semibold)
        default:
            return bodyFont
        }
    }

    private func baseForegroundColor(for blockKind: BlockKind?) -> Color {
        switch blockKind {
        case .blockquote, .taskChecked:
            return DesignTokens.Colors.textSecondary
        default:
            return DesignTokens.Colors.textPrimary
        }
    }

    private func baseBackgroundColor(for blockKind: BlockKind?) -> Color? {
        switch blockKind {
        case .codeBlock:
            return style.codeBlockBackground
        default:
            return nil
        }
    }

    private func hasInlineIntent(_ intent: InlinePresentationIntent) -> Bool {
        let attrs = selection.typingAttributes(in: attributedContent)
        let intents = attrs.inlinePresentationIntent ?? []
        return intents.contains(intent)
    }

    private func applyInlineIntent(
        _ intent: InlinePresentationIntent,
        enabled: Bool,
        range: Range<AttributedString.Index>? = nil
    ) {
        if let range {
            applyInlineIntentToRange(intent, enabled: enabled, range: range)
            return
        }
        attributedContent.transformAttributes(in: &selection) { attrs in
            updateInlineIntent(intent, enabled: enabled, attrs: &attrs)
        }
    }

    private func updateInlineIntent(
        _ intent: InlinePresentationIntent,
        enabled: Bool,
        attrs: inout AttributeContainer
    ) {
        var intents = attrs.inlinePresentationIntent ?? []
        if enabled {
            intents.insert(intent)
        } else {
            intents.remove(intent)
        }
        attrs.inlinePresentationIntent = intents

        if intent == .code {
            let blockKind = attrs.blockKind
            if enabled {
                attrs.font = inlineCodeFont
                attrs.foregroundColor = DesignTokens.Colors.textPrimary
                attrs.backgroundColor = style.codeBackground
            } else {
                attrs.font = baseFont(for: blockKind)
                attrs.foregroundColor = baseForegroundColor(for: blockKind)
                attrs.backgroundColor = baseBackgroundColor(for: blockKind)
            }
        }
    }

    private func applyInlineIntentToRange(
        _ intent: InlinePresentationIntent,
        enabled: Bool,
        range: Range<AttributedString.Index>
    ) {
        var intents = attributedContent[range].inlinePresentationIntent ?? []
        if enabled {
            intents.insert(intent)
        } else {
            intents.remove(intent)
        }
        attributedContent[range].inlinePresentationIntent = intents

        guard intent == .code else { return }

        if enabled {
            attributedContent[range].font = inlineCodeFont
            attributedContent[range].foregroundColor = DesignTokens.Colors.textPrimary
            attributedContent[range].backgroundColor = style.codeBackground
        } else {
            let blockKind = attributedContent.blockKind(in: range)
            attributedContent[range].font = baseFont(for: blockKind)
            attributedContent[range].foregroundColor = baseForegroundColor(for: blockKind)
            attributedContent[range].backgroundColor = baseBackgroundColor(for: blockKind)
        }
    }

    private func applyBlockStyle(blockKind: BlockKind, range: Range<AttributedString.Index>) {
        let font = blockKind == .codeBlock ? blockCodeFont : baseFont(for: blockKind)
        attributedContent[range].font = font
        attributedContent[range].foregroundColor = baseForegroundColor(for: blockKind)
        attributedContent[range].backgroundColor = baseBackgroundColor(for: blockKind)
        if let paragraphStyle = paragraphStyle(for: blockKind) {
            attributedContent[range].paragraphStyle = paragraphStyle
        }
        if blockKind == .taskChecked {
            attributedContent[range].strikethroughStyle = .single
            attributedContent[range].foregroundColor = DesignTokens.Colors.textSecondary
        }
    }

    private func applyPresentationIntent(
        blockKind: BlockKind,
        listDepth: Int?,
        range: Range<AttributedString.Index>
    ) {
        switch blockKind {
        case .heading1:
            attributedContent[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(.header(level: 1), identity: 1)
        case .heading2:
            attributedContent[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(.header(level: 2), identity: 2)
        case .heading3:
            attributedContent[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(.header(level: 3), identity: 3)
        case .heading4:
            attributedContent[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(.header(level: 4), identity: 4)
        case .heading5:
            attributedContent[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(.header(level: 5), identity: 5)
        case .heading6:
            attributedContent[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(.header(level: 6), identity: 6)
        case .blockquote:
            let quoteIntent = PresentationIntent(.blockQuote, identity: 1)
            attributedContent[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(.paragraph, identity: 1, parent: quoteIntent)
        case .codeBlock:
            attributedContent[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(.codeBlock(languageHint: nil), identity: 1)
        case .horizontalRule:
            attributedContent[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(.thematicBreak, identity: 1)
        case .bulletList, .orderedList, .taskChecked, .taskUnchecked:
            let listKind: PresentationIntent.Kind = blockKind == .orderedList ? .orderedList : .unorderedList
            let listId = listDepth ?? 1
            let listIntent = PresentationIntent(listKind, identity: listId)
            let listItemIntent = PresentationIntent(.listItem(ordinal: 1), identity: listId * 1000 + 1, parent: listIntent)
            attributedContent[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(.paragraph, identity: 1, parent: listItemIntent)
            if blockKind == .bulletList {
                attributedContent[range][AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = "•"
            } else if blockKind == .taskChecked {
                attributedContent[range][AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = "☑"
            } else if blockKind == .taskUnchecked {
                attributedContent[range][AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = "☐"
            } else {
                attributedContent[range][AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = nil
            }
        case .paragraph, .blankLine, .imageCaption, .gallery, .htmlBlock:
            attributedContent[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(.paragraph, identity: 1)
        }
    }

    private func selectionRanges() -> RangeSet<AttributedString.Index> {
        switch selection.indices(in: attributedContent) {
        case .insertionPoint(let index):
            return RangeSet([index..<index])
        case .ranges(let ranges):
            return ranges
        }
    }

    private func updatePrefixVisibility() {
        var updated = attributedContent
        var selectionCopy = selection
        var didUpdateTypingAttributes = false

        for lineRange in lineRanges(in: updated) {
            let lineText = String(updated[lineRange].characters)
            let prefixRange = markdownPrefixRange(in: updated, lineRange: lineRange, lineText: lineText)
            let shouldShow = shouldShowPrefix(for: lineRange, selection: selection, in: updated)
            let blockKind = updated.blockKind(in: lineRange) ?? inferredBlockKind(from: lineText)

            if let prefixRange {
                if shouldShow {
                    updated[prefixRange].foregroundColor = DesignTokens.Colors.textSecondary
                    updated[prefixRange].backgroundColor = baseBackgroundColor(for: blockKind)
                    updated[prefixRange].font = baseFont(for: blockKind)
                } else {
                    updated[prefixRange].foregroundColor = .clear
                    updated[prefixRange].backgroundColor = nil
                    updated[prefixRange].font = .system(size: 0.1)
                }
            }

            let inlineRanges = ensureInlineMarkerRanges(in: &updated, lineRange: lineRange, lineText: lineText)
            for inlineRange in inlineRanges {
                if shouldShow {
                    updated[inlineRange].foregroundColor = DesignTokens.Colors.textSecondary
                    updated[inlineRange].backgroundColor = nil
                    updated[inlineRange].font = inlineMarkerFont(
                        for: inlineRange,
                        lineRange: lineRange,
                        in: updated,
                        fallback: baseFont(for: blockKind)
                    )
                } else {
                    updated[inlineRange].foregroundColor = .clear
                    updated[inlineRange].backgroundColor = nil
                    updated[inlineRange].font = .system(size: 0.1)
                }
            }

            guard !didUpdateTypingAttributes else { continue }
            if case .insertionPoint(let index) = selectionCopy.indices(in: updated),
               (lineRange.contains(index) || index == lineRange.upperBound) {
                if let prefixRange,
                   prefixRange.contains(index) || index == prefixRange.upperBound {
                    updated.transformAttributes(in: &selectionCopy) { attrs in
                        attrs.foregroundColor = baseForegroundColor(for: blockKind)
                        attrs.backgroundColor = baseBackgroundColor(for: blockKind)
                    }
                    didUpdateTypingAttributes = true
                    continue
                }

                if inlineRanges.contains(where: { $0.contains(index) || index == $0.upperBound }) {
                    updated.transformAttributes(in: &selectionCopy) { attrs in
                        attrs.foregroundColor = baseForegroundColor(for: blockKind)
                        attrs.backgroundColor = baseBackgroundColor(for: blockKind)
                    }
                    didUpdateTypingAttributes = true
                }
            }
        }

        if updated != attributedContent || didUpdateTypingAttributes {
            isUpdatingPrefixVisibility = true
            attributedContent = updated
            selection = selectionCopy
            Task { @MainActor [weak self] in
                self?.isUpdatingPrefixVisibility = false
            }
        }
    }

    private func lineRanges(in text: AttributedString) -> [Range<AttributedString.Index>] {
        var lines: [Range<AttributedString.Index>] = []
        var start = text.startIndex
        var current = text.startIndex

        while current < text.endIndex {
            if text.characters[current] == "\n" {
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

    private func lineIndexForSelection(in text: AttributedString) -> Int? {
        let ranges = lineRanges(in: text)
        let selectionIndex: AttributedString.Index?

        switch selection.indices(in: text) {
        case .insertionPoint(let index):
            selectionIndex = index
        case .ranges(let set):
            selectionIndex = set.ranges.first?.lowerBound
        }

        guard let selectionIndex else { return nil }

        for (lineIndex, range) in ranges.enumerated() {
            if range.contains(selectionIndex) || selectionIndex == range.upperBound {
                return lineIndex
            }
        }
        return nil
    }

    private func markdownPrefixRange(
        in text: AttributedString,
        lineRange: Range<AttributedString.Index>,
        lineText: String
    ) -> Range<AttributedString.Index>? {
        let range = NSRange(location: 0, length: lineText.utf16.count)
        let regexes = [
            Self.taskRegex,
            Self.orderedRegex,
            Self.bulletRegex,
            Self.headingRegex,
            Self.quoteRegex
        ]

        for regex in regexes {
            guard let regex, let match = regex.firstMatch(in: lineText, range: range) else { continue }
            guard let matchRange = Range(match.range, in: lineText) else { continue }
            let prefixCount = lineText.distance(from: lineText.startIndex, to: matchRange.upperBound)
            let prefixEnd = text.index(lineRange.lowerBound, offsetByCharacters: prefixCount)
            return lineRange.lowerBound..<prefixEnd
        }

        return nil
    }

    private func inlineMarkerRanges(
        in text: AttributedString,
        lineRange: Range<AttributedString.Index>
    ) -> [Range<AttributedString.Index>] {
        var ranges: [Range<AttributedString.Index>] = []
        for run in text[lineRange].runs {
            guard run.inlineMarker == true else { continue }
            ranges.append(run.range)
        }
        return ranges
    }

    private func ensureInlineMarkerRanges(
        in text: inout AttributedString,
        lineRange: Range<AttributedString.Index>,
        lineText: String
    ) -> [Range<AttributedString.Index>] {
        let attributedRanges = inlineMarkerRanges(in: text, lineRange: lineRange)
        if !attributedRanges.isEmpty {
            return attributedRanges
        }

        let patterns = [
            #"\*\*"#,
            #"__"#,
            #"~~"#,
            #"(?<!\*)\*(?!\*)"#,
            #"(?<!_)_(?!_)"#,
            #"(?<!`)`(?!`)"#
        ]
        var ranges: [Range<AttributedString.Index>] = []

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let nsRange = NSRange(location: 0, length: lineText.utf16.count)
            for match in regex.matches(in: lineText, range: nsRange) {
                guard let matchRange = Range(match.range, in: lineText) else { continue }
                let startOffset = lineText.distance(from: lineText.startIndex, to: matchRange.lowerBound)
                let endOffset = lineText.distance(from: lineText.startIndex, to: matchRange.upperBound)
                let start = text.index(lineRange.lowerBound, offsetByCharacters: startOffset)
                let end = text.index(lineRange.lowerBound, offsetByCharacters: endOffset)
                let range = start..<end
                text[range].inlineMarker = true
                ranges.append(range)
            }
        }

        return ranges
    }

    private func inlineMarkerFont(
        for markerRange: Range<AttributedString.Index>,
        lineRange: Range<AttributedString.Index>,
        in text: AttributedString,
        fallback: Font
    ) -> Font {
        if markerRange.upperBound < lineRange.upperBound {
            if let font = font(at: markerRange.upperBound, in: text, lineRange: lineRange) {
                return font
            }
        }
        if markerRange.lowerBound > lineRange.lowerBound {
            let beforeIndex = text.index(beforeCharacter: markerRange.lowerBound)
            if let font = font(at: beforeIndex, in: text, lineRange: lineRange) {
                return font
            }
        }
        return fallback
    }

    private func font(
        at index: AttributedString.Index,
        in text: AttributedString,
        lineRange: Range<AttributedString.Index>
    ) -> Font? {
        guard lineRange.contains(index) else { return nil }
        let nextIndex = text.index(afterCharacter: index)
        guard nextIndex <= text.endIndex else { return nil }
        return text[index..<nextIndex].font
    }

    private func inferredBlockKind(from lineText: String) -> BlockKind? {
        let range = NSRange(location: 0, length: lineText.utf16.count)

        if let regex = Self.taskRegex, let match = regex.firstMatch(in: lineText, range: range) {
            let prefix = (lineText as NSString).substring(with: match.range).lowercased()
            return prefix.contains("[x]") ? .taskChecked : .taskUnchecked
        }
        if Self.orderedRegex?.firstMatch(in: lineText, range: range) != nil {
            return .orderedList
        }
        if Self.bulletRegex?.firstMatch(in: lineText, range: range) != nil {
            return .bulletList
        }
        if let regex = Self.headingRegex, let match = regex.firstMatch(in: lineText, range: range) {
            let prefix = (lineText as NSString).substring(with: match.range)
            let count = prefix.prefix { $0 == "#" }.count
            switch count {
            case 1: return .heading1
            case 2: return .heading2
            case 3: return .heading3
            case 4: return .heading4
            case 5: return .heading5
            case 6: return .heading6
            default: return nil
            }
        }
        if Self.quoteRegex?.firstMatch(in: lineText, range: range) != nil {
            return .blockquote
        }
        return nil
    }

    private func shouldShowPrefix(
        for lineRange: Range<AttributedString.Index>,
        selection: AttributedTextSelection,
        in text: AttributedString
    ) -> Bool {
        if isReadOnly {
            return false
        }
        switch selection.indices(in: text) {
        case .insertionPoint(let index):
            return lineRange.contains(index) || index == lineRange.upperBound
        case .ranges(let ranges):
            return ranges.ranges.contains { range in
                if range.isEmpty {
                    return lineRange.contains(range.lowerBound) || range.lowerBound == lineRange.upperBound
                }
                return range.overlaps(lineRange)
            }
        }
    }

    private func paragraphStyle(for blockKind: BlockKind) -> NSParagraphStyle? {
        switch blockKind {
        case .heading1:
            return paragraphStyle(
                lineSpacing: em(0.3, fontSize: heading1FontSize),
                spacingBefore: 0,
                spacingAfter: rem(0.3)
            )
        case .heading2:
            return paragraphStyle(
                lineSpacing: em(0.3, fontSize: heading2FontSize),
                spacingBefore: rem(1),
                spacingAfter: rem(0.3)
            )
        case .heading3:
            return paragraphStyle(
                lineSpacing: em(0.3, fontSize: heading3FontSize),
                spacingBefore: rem(1),
                spacingAfter: rem(0.3)
            )
        case .heading4:
            return paragraphStyle(
                lineSpacing: em(0.3, fontSize: heading4FontSize),
                spacingBefore: rem(1),
                spacingAfter: rem(0.3)
            )
        case .heading5:
            return paragraphStyle(
                lineSpacing: em(0.3, fontSize: heading5FontSize),
                spacingBefore: rem(1),
                spacingAfter: rem(0.3)
            )
        case .heading6:
            return paragraphStyle(
                lineSpacing: em(0.3, fontSize: heading6FontSize),
                spacingBefore: rem(1),
                spacingAfter: rem(0.3)
            )
        case .paragraph:
            return paragraphStyle(
                lineSpacing: em(0.2, fontSize: baseFontSize),
                spacingBefore: rem(0.5),
                spacingAfter: rem(0.5)
            )
        case .blockquote:
            return paragraphStyle(
                lineSpacing: em(0.7, fontSize: baseFontSize),
                spacingBefore: em(1, fontSize: baseFontSize),
                spacingAfter: em(1, fontSize: baseFontSize),
                headIndent: em(1, fontSize: baseFontSize)
            )
        case .bulletList, .orderedList, .taskChecked, .taskUnchecked:
            return paragraphStyle(
                lineSpacing: em(0.2, fontSize: baseFontSize),
                spacingBefore: 0,
                spacingAfter: 0
            )
        case .codeBlock:
            return paragraphStyle(
                lineSpacing: em(0.5, fontSize: inlineCodeFontSize),
                spacingBefore: 0,
                spacingAfter: 0
            )
        case .horizontalRule:
            return paragraphStyle(
                lineSpacing: 0,
                spacingBefore: rem(1.5),
                spacingAfter: rem(1.5)
            )
        case .imageCaption:
            return paragraphStyle(
                lineSpacing: 0,
                spacingBefore: rem(0.25),
                spacingAfter: rem(0.75)
            )
        case .blankLine, .gallery, .htmlBlock:
            return paragraphStyle(
                lineSpacing: 0,
                spacingBefore: 0,
                spacingAfter: 0
            )
        }
    }

    private func rem(_ value: CGFloat) -> CGFloat {
        value * baseFontSize
    }

    private func em(_ value: CGFloat, fontSize: CGFloat) -> CGFloat {
        value * fontSize
    }

    private func paragraphStyle(
        lineSpacing: CGFloat,
        spacingBefore: CGFloat,
        spacingAfter: CGFloat,
        headIndent: CGFloat = 0
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacingBefore = spacingBefore
        style.paragraphSpacing = spacingAfter
        style.headIndent = headIndent
        style.firstLineHeadIndent = headIndent
        return style
    }
}

@available(iOS 26.0, macOS 26.0, *)
public enum MarkdownFormatting {
    case bold
    case italic
    case strikethrough
    case inlineCode
    case heading(level: Int)
    case bulletList
    case orderedList
    case taskList
    case blockquote
    case codeBlock
    case link(URL)
    case horizontalRule
}
