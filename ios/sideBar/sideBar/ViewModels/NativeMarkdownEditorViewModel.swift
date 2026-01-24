import Foundation
import Combine
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
public final class NativeMarkdownEditorViewModel: ObservableObject {
    @Published public var attributedContent: AttributedString = AttributedString()
    @Published public var selection: AttributedTextSelection = AttributedTextSelection()
    @Published public var isReadOnly: Bool = false
    @Published public private(set) var hasUnsavedChanges: Bool = false

    private let importer = MarkdownImporter()
    private let exporter = MarkdownExporter()
    private let bodyFont = Font.system(size: 16)
    private let inlineCodeFont = Font.system(size: 14, weight: .regular, design: .monospaced)
    private let blockCodeFont = Font.system(size: 14, weight: .regular, design: .monospaced)
    private var frontmatter: String?
    private var lastSavedContent: String = ""
    private var autosaveTask: Task<Void, Never>?
    private var isApplyingShortcut = false

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
            try? await Task.sleep(for: .seconds(0.6))
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
            return .system(size: 32, weight: .bold)
        case .heading2:
            return .system(size: 24, weight: .semibold)
        case .heading3:
            return .system(size: 20, weight: .semibold)
        case .heading4:
            return .system(size: 18, weight: .semibold)
        case .heading5:
            return .system(size: 17, weight: .semibold)
        case .heading6:
            return .system(size: 16, weight: .semibold)
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
            return DesignTokens.Colors.muted
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
                attrs.backgroundColor = DesignTokens.Colors.muted
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
            attributedContent[range].backgroundColor = DesignTokens.Colors.muted
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
        if blockKind == .taskChecked {
            attributedContent[range].strikethroughStyle = .single
            attributedContent[range].foregroundColor = DesignTokens.Colors.textSecondary
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
