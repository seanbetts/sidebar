@preconcurrency import Foundation
import Combine
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

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

#if os(iOS)
    private typealias PlatformFont = UIFont
    private typealias PlatformFontWeight = UIFont.Weight
    private typealias PlatformColor = UIColor
#elseif os(macOS)
    private typealias PlatformFont = NSFont
    private typealias PlatformFontWeight = NSFont.Weight
    private typealias PlatformColor = NSColor
#endif

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
        updatePrefixVisibility()
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
            setForegroundColor(.accentColor, in: &attrs)
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
        lastSelectionLineIndex = lineIndexForSelection(in: attributedContent)
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
                setForegroundColor(DesignTokens.Colors.textSecondary, range: range)
            } else {
                attributedContent[range].strikethroughStyle = nil
                let blockKind = attributedContent.blockKind(in: range)
                setForegroundColor(baseForegroundColor(for: blockKind), range: range)
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
            if attributedContent.characters[prev].isNewline {
                break
            }
            start = prev
        }

        while end < attributedContent.endIndex {
            if attributedContent.characters[end].isNewline {
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
            setForegroundColor(.accentColor, range: range)
            attributedContent[range].underlineStyle = .single
        }
    }

    private func insertHorizontalRule() {
        var hr = AttributedString("---")
        let range = hr.startIndex..<hr.endIndex
        hr[range].blockKind = .horizontalRule
        setForegroundColor(DesignTokens.Colors.border, in: &hr, range: range)

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
        case .codeBlock:
            return blockCodeFont
        case .imageCaption:
            return DesignTokens.Typography.footnote
        default:
            return bodyFont
        }
    }

    private func platformBaseFont(for blockKind: BlockKind?) -> PlatformFont {
        switch blockKind {
        case .heading1:
            return platformSystemFont(size: heading1FontSize, weight: .bold)
        case .heading2:
            return platformSystemFont(size: heading2FontSize, weight: .semibold)
        case .heading3:
            return platformSystemFont(size: heading3FontSize, weight: .semibold)
        case .heading4:
            return platformSystemFont(size: heading4FontSize, weight: .semibold)
        case .heading5:
            return platformSystemFont(size: heading5FontSize, weight: .semibold)
        case .heading6:
            return platformSystemFont(size: heading6FontSize, weight: .semibold)
        case .codeBlock:
            return platformSystemFont(size: inlineCodeFontSize, weight: .regular, monospaced: true)
        case .imageCaption:
            return platformFootnoteFont()
        default:
            return platformSystemFont(size: baseFontSize, weight: .regular)
        }
    }

    private func platformInlineCodeFont() -> PlatformFont {
        platformSystemFont(size: inlineCodeFontSize, weight: .regular, monospaced: true)
    }

    private func platformFootnoteFont() -> PlatformFont {
#if os(iOS)
        return UIFont.preferredFont(forTextStyle: .footnote)
#else
        return NSFont.preferredFont(forTextStyle: .footnote)
#endif
    }

    private func platformSystemFont(
        size: CGFloat,
        weight: PlatformFontWeight,
        monospaced: Bool = false
    ) -> PlatformFont {
#if os(iOS)
        return monospaced
            ? UIFont.monospacedSystemFont(ofSize: size, weight: weight)
            : UIFont.systemFont(ofSize: size, weight: weight)
#else
        return monospaced
            ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
            : NSFont.systemFont(ofSize: size, weight: weight)
#endif
    }

    private func platformFontApplyingTraits(
        _ font: PlatformFont,
        bold: Bool,
        italic: Bool
    ) -> PlatformFont {
#if os(iOS)
        var traits = font.fontDescriptor.symbolicTraits
        if bold { traits.insert(.traitBold) } else { traits.remove(.traitBold) }
        if italic { traits.insert(.traitItalic) } else { traits.remove(.traitItalic) }
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(traits) else { return font }
        return UIFont(descriptor: descriptor, size: font.pointSize)
#else
        var traits = font.fontDescriptor.symbolicTraits
        if bold { traits.insert(.bold) } else { traits.remove(.bold) }
        if italic { traits.insert(.italic) } else { traits.remove(.italic) }
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(traits) else { return font }
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
#endif
    }

    private func baseForegroundColor(for blockKind: BlockKind?) -> Color {
        switch blockKind {
        case .blockquote, .taskChecked, .htmlBlock, .gallery:
            return DesignTokens.Colors.textSecondary
        case .imageCaption:
            return DesignTokens.Colors.textTertiary
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

    private func tableRowInfo(from intent: PresentationIntent?) -> (isHeader: Bool, rowIndex: Int?)? {
        guard let intent else { return nil }
        var isHeader = false
        var rowIndex: Int?
        var foundRow = false

        for component in intent.components {
            switch component.kind {
            case .tableHeaderRow:
                isHeader = true
                rowIndex = 0
                foundRow = true
            case .tableRow(let index):
                rowIndex = index
                foundRow = true
            default:
                break
            }
        }

        guard foundRow else { return nil }
        return (isHeader: isHeader, rowIndex: rowIndex)
    }

    private func tableRowBackground(from info: (isHeader: Bool, rowIndex: Int?)?) -> Color? {
        guard let info else { return nil }
        if info.isHeader {
            return DesignTokens.Colors.muted
        }
        if let rowIndex = info.rowIndex, rowIndex % 2 == 1 {
            return DesignTokens.Colors.muted.opacity(0.4)
        }
        return nil
    }

    private func platformColor(_ color: Color) -> PlatformColor {
#if os(iOS)
        UIColor(color)
#else
        NSColor(color)
#endif
    }

    private func platformColor(_ color: Color?) -> PlatformColor? {
        guard let color else { return nil }
        return platformColor(color)
    }

    private func setFont(_ font: Font, platformFont: PlatformFont, in attrs: inout AttributeContainer) {
        attrs.font = font
        setPlatformFont(platformFont, in: &attrs)
    }

    private func setForegroundColor(_ color: Color, in attrs: inout AttributeContainer) {
        attrs.foregroundColor = color
        setPlatformForegroundColor(platformColor(color), in: &attrs)
    }

    private func setBackgroundColor(_ color: Color?, in attrs: inout AttributeContainer) {
        attrs.backgroundColor = color
        setPlatformBackgroundColor(platformColor(color), in: &attrs)
    }

    private func setFont(
        _ font: Font,
        platformFont: PlatformFont,
        in text: inout AttributedString,
        range: Range<AttributedString.Index>
    ) {
        text[range].font = font
        setPlatformFont(platformFont, in: &text, range: range)
    }

    private func setForegroundColor(
        _ color: Color,
        in text: inout AttributedString,
        range: Range<AttributedString.Index>
    ) {
        text[range].foregroundColor = color
        setPlatformForegroundColor(platformColor(color), in: &text, range: range)
    }

    private func setForegroundColor(_ color: Color, range: Range<AttributedString.Index>) {
        setForegroundColor(color, in: &attributedContent, range: range)
    }

    private func setBackgroundColor(
        _ color: Color?,
        in text: inout AttributedString,
        range: Range<AttributedString.Index>
    ) {
        text[range].backgroundColor = color
        setPlatformBackgroundColor(platformColor(color), in: &text, range: range)
    }

    private func setBackgroundColor(_ color: Color?, range: Range<AttributedString.Index>) {
        setBackgroundColor(color, in: &attributedContent, range: range)
    }

    private func setPlatformFont(_ font: PlatformFont, in attrs: inout AttributeContainer) {
#if os(iOS)
        attrs[AttributeScopes.UIKitAttributes.FontAttribute.self] = font
#else
        attrs[AttributeScopes.AppKitAttributes.FontAttribute.self] = font
#endif
    }

    private func setPlatformForegroundColor(_ color: PlatformColor, in attrs: inout AttributeContainer) {
#if os(iOS)
        attrs[AttributeScopes.UIKitAttributes.ForegroundColorAttribute.self] = color
#else
        attrs[AttributeScopes.AppKitAttributes.ForegroundColorAttribute.self] = color
#endif
    }

    private func setPlatformBackgroundColor(_ color: PlatformColor?, in attrs: inout AttributeContainer) {
#if os(iOS)
        attrs[AttributeScopes.UIKitAttributes.BackgroundColorAttribute.self] = color
#else
        attrs[AttributeScopes.AppKitAttributes.BackgroundColorAttribute.self] = color
#endif
    }

    private func setPlatformFont(
        _ font: PlatformFont,
        in text: inout AttributedString,
        range: Range<AttributedString.Index>
    ) {
#if os(iOS)
        text[range][AttributeScopes.UIKitAttributes.FontAttribute.self] = font
#else
        text[range][AttributeScopes.AppKitAttributes.FontAttribute.self] = font
#endif
    }

    private func setPlatformForegroundColor(
        _ color: PlatformColor,
        in text: inout AttributedString,
        range: Range<AttributedString.Index>
    ) {
#if os(iOS)
        text[range][AttributeScopes.UIKitAttributes.ForegroundColorAttribute.self] = color
#else
        text[range][AttributeScopes.AppKitAttributes.ForegroundColorAttribute.self] = color
#endif
    }

    private func setPlatformBackgroundColor(
        _ color: PlatformColor?,
        in text: inout AttributedString,
        range: Range<AttributedString.Index>
    ) {
#if os(iOS)
        text[range][AttributeScopes.UIKitAttributes.BackgroundColorAttribute.self] = color
#else
        text[range][AttributeScopes.AppKitAttributes.BackgroundColorAttribute.self] = color
#endif
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
                setFont(inlineCodeFont, platformFont: platformInlineCodeFont(), in: &attrs)
                setForegroundColor(DesignTokens.Colors.textPrimary, in: &attrs)
                setBackgroundColor(style.codeBackground, in: &attrs)
            } else {
                setFont(baseFont(for: blockKind), platformFont: platformBaseFont(for: blockKind), in: &attrs)
                setForegroundColor(baseForegroundColor(for: blockKind), in: &attrs)
                setBackgroundColor(baseBackgroundColor(for: blockKind), in: &attrs)
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
            setFont(inlineCodeFont, platformFont: platformInlineCodeFont(), in: &attributedContent, range: range)
            setForegroundColor(DesignTokens.Colors.textPrimary, in: &attributedContent, range: range)
            setBackgroundColor(style.codeBackground, in: &attributedContent, range: range)
        } else {
            let blockKind = attributedContent.blockKind(in: range)
            setFont(baseFont(for: blockKind), platformFont: platformBaseFont(for: blockKind), in: &attributedContent, range: range)
            setForegroundColor(baseForegroundColor(for: blockKind), in: &attributedContent, range: range)
            setBackgroundColor(baseBackgroundColor(for: blockKind), in: &attributedContent, range: range)
        }
    }

    private func applyBlockStyle(blockKind: BlockKind, range: Range<AttributedString.Index>) {
        let font = blockKind == .codeBlock ? blockCodeFont : baseFont(for: blockKind)
        let platformFont = blockKind == .codeBlock ? platformInlineCodeFont() : platformBaseFont(for: blockKind)
        setFont(font, platformFont: platformFont, in: &attributedContent, range: range)
        setForegroundColor(baseForegroundColor(for: blockKind), in: &attributedContent, range: range)
        setBackgroundColor(baseBackgroundColor(for: blockKind), in: &attributedContent, range: range)
        let listDepth = attributedContent[range].listDepth
        if let paragraphStyle = paragraphStyle(for: blockKind, listDepth: listDepth) {
            attributedContent[range].paragraphStyle = paragraphStyle
        }
        if blockKind == .taskChecked {
            attributedContent[range].strikethroughStyle = .single
            setForegroundColor(DesignTokens.Colors.textSecondary, in: &attributedContent, range: range)
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

    private enum SelectionSnapshot {
        case insertionPoint(Int)
        case ranges([Range<Int>])
    }

    private struct LineInfo {
        let range: Range<Int>
        let text: String
    }

    private func selectionSnapshot(in text: AttributedString) -> SelectionSnapshot {
        switch selection.indices(in: text) {
        case .insertionPoint(let index):
            let offset = text.characters.distance(from: text.startIndex, to: index)
            return .insertionPoint(offset)
        case .ranges(let ranges):
            let offsets = ranges.ranges.map { range in
                let lower = text.characters.distance(from: text.startIndex, to: range.lowerBound)
                let upper = text.characters.distance(from: text.startIndex, to: range.upperBound)
                return lower..<upper
            }
            return .ranges(offsets)
        }
    }

    private func selection(from snapshot: SelectionSnapshot, in text: AttributedString) -> AttributedTextSelection {
        let maxOffset = text.characters.count
        func index(for offset: Int) -> AttributedString.Index {
            let clamped = min(max(offset, 0), maxOffset)
            return text.index(text.startIndex, offsetByCharacters: clamped)
        }

        switch snapshot {
        case .insertionPoint(let offset):
            let index = index(for: offset)
            return AttributedTextSelection(range: index..<index)
        case .ranges(let offsets):
            let ranges = offsets.map { range -> Range<AttributedString.Index> in
                let lower = index(for: range.lowerBound)
                let upper = index(for: range.upperBound)
                return lower..<upper
            }
            return AttributedTextSelection(ranges: RangeSet(ranges))
        }
    }

    private func updatePrefixVisibility() {
        let selectionSnapshot = selectionSnapshot(in: attributedContent)
        var updated = attributedContent

        let lines = lineInfos(in: updated)
        applyCodeBlockSpacing(in: &updated, lines: lines)
        for line in lines {
            let lineStart = updated.index(updated.startIndex, offsetByCharacters: line.range.lowerBound)
            let lineEnd = updated.index(updated.startIndex, offsetByCharacters: line.range.upperBound)
            let lineRange = lineStart..<lineEnd
            let shouldShow = shouldShowPrefix(for: line.range, selection: selectionSnapshot)
            let blockKind = updated.blockKind(in: lineRange) ?? inferredBlockKind(from: line.text)
            let prefixRange = markdownPrefixRange(
                in: updated,
                lineRange: lineRange,
                lineText: line.text,
                blockKind: blockKind
            )

            applyInlineIntentStyling(in: &updated, lineRange: lineRange, blockKind: blockKind)

            if let prefixRange {
                if shouldShow {
                    setForegroundColor(DesignTokens.Colors.textSecondary, in: &updated, range: prefixRange)
                    setBackgroundColor(baseBackgroundColor(for: blockKind), in: &updated, range: prefixRange)
                    setFont(
                        baseFont(for: blockKind),
                        platformFont: platformBaseFont(for: blockKind),
                        in: &updated,
                        range: prefixRange
                    )
                } else {
                    setForegroundColor(.clear, in: &updated, range: prefixRange)
                    setBackgroundColor(nil, in: &updated, range: prefixRange)
                    setFont(
                        .system(size: 0.1),
                        platformFont: platformSystemFont(size: 0.1, weight: .regular),
                        in: &updated,
                        range: prefixRange
                    )
                }
            }

            let inlineRanges = ensureInlineMarkerRanges(in: &updated, lineRange: lineRange, lineText: line.text)
            for inlineRange in inlineRanges {
                if shouldShow {
                    setForegroundColor(DesignTokens.Colors.textSecondary, in: &updated, range: inlineRange)
                    setBackgroundColor(nil, in: &updated, range: inlineRange)
                    setFont(
                        baseFont(for: blockKind),
                        platformFont: platformBaseFont(for: blockKind),
                        in: &updated,
                        range: inlineRange
                    )
                } else {
                    setForegroundColor(.clear, in: &updated, range: inlineRange)
                    setBackgroundColor(nil, in: &updated, range: inlineRange)
                    setFont(
                        .system(size: 0.1),
                        platformFont: platformSystemFont(size: 0.1, weight: .regular),
                        in: &updated,
                        range: inlineRange
                    )
                }
            }
        }

        if updated != attributedContent {
            isUpdatingPrefixVisibility = true
            attributedContent = updated
            selection = selection(from: selectionSnapshot, in: updated)
            Task { @MainActor [weak self] in
                self?.isUpdatingPrefixVisibility = false
            }
        }
    }

    private func applyCodeBlockSpacing(in text: inout AttributedString, lines: [LineInfo]) {
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

            for lineIndex in index...endIndex {
                let info = lines[lineIndex]
                let start = text.index(text.startIndex, offsetByCharacters: info.range.lowerBound)
                let end = text.index(text.startIndex, offsetByCharacters: info.range.upperBound)
                let range = start..<end
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

            index = endIndex + 1
        }
    }

    private func lineRanges(in text: AttributedString) -> [Range<AttributedString.Index>] {
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
        lineText: String,
        blockKind: BlockKind?
    ) -> Range<AttributedString.Index>? {
        if blockKind == .horizontalRule {
            return lineRange
        }
        if let blockKind, let range = prefixRangeForBlockKind(
            blockKind,
            in: text,
            lineRange: lineRange,
            lineText: lineText
        ) {
            return range
        }

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

    private func prefixRangeForBlockKind(
        _ blockKind: BlockKind,
        in text: AttributedString,
        lineRange: Range<AttributedString.Index>,
        lineText: String
    ) -> Range<AttributedString.Index>? {
        let prefix: String
        switch blockKind {
        case .heading1:
            prefix = "# "
        case .heading2:
            prefix = "## "
        case .heading3:
            prefix = "### "
        case .heading4:
            prefix = "#### "
        case .heading5:
            prefix = "##### "
        case .heading6:
            prefix = "###### "
        default:
            return nil
        }

        guard let firstNonWhitespace = lineText.firstIndex(where: { !$0.isWhitespace }) else {
            return nil
        }
        guard lineText[firstNonWhitespace...].hasPrefix(prefix) else {
            return nil
        }

        let leadingOffset = lineText.distance(from: lineText.startIndex, to: firstNonWhitespace)
        let prefixEnd = text.index(lineRange.lowerBound, offsetByCharacters: leadingOffset + prefix.count)
        return lineRange.lowerBound..<prefixEnd
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

    private func applyInlineIntentStyling(
        in text: inout AttributedString,
        lineRange: Range<AttributedString.Index>,
        blockKind: BlockKind?
    ) {
        let baseFont = baseFont(for: blockKind)
        let baseBackground = baseBackgroundColor(for: blockKind)
        let baseForeground = baseForegroundColor(for: blockKind)
        let basePlatformFont = platformBaseFont(for: blockKind)
        for run in text[lineRange].runs {
            guard run.inlineMarker != true else { continue }
            let intents = run.inlinePresentationIntent ?? []
            let range = run.range
            let tableInfo = tableRowInfo(from: run[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self])

            if intents.contains(.code) {
                setFont(inlineCodeFont, platformFont: platformInlineCodeFont(), in: &text, range: range)
                setForegroundColor(DesignTokens.Colors.textPrimary, in: &text, range: range)
                setBackgroundColor(style.codeBackground, in: &text, range: range)
                continue
            }

            var font = baseFont
            if intents.contains(.emphasized) {
                font = font.italic()
            }
            if intents.contains(.stronglyEmphasized) {
                font = font.weight(.bold)
            }
            if tableInfo?.isHeader == true {
                font = font.weight(.semibold)
            }
            let platformFont = platformFontApplyingTraits(
                basePlatformFont,
                bold: intents.contains(.stronglyEmphasized) || tableInfo?.isHeader == true,
                italic: intents.contains(.emphasized)
            )
            setFont(font, platformFont: platformFont, in: &text, range: range)
            let tableBackground = tableRowBackground(from: tableInfo)
            if let baseBackground {
                setBackgroundColor(baseBackground, in: &text, range: range)
            } else if let tableBackground {
                setBackgroundColor(tableBackground, in: &text, range: range)
            }
            if run.link != nil {
                setForegroundColor(.accentColor, in: &text, range: range)
            } else if run.strikethroughStyle != nil || run.imageInfo != nil {
                setForegroundColor(DesignTokens.Colors.textSecondary, in: &text, range: range)
            } else {
                setForegroundColor(baseForeground, in: &text, range: range)
            }
        }
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
        for lineRange: Range<Int>,
        selection: SelectionSnapshot
    ) -> Bool {
        guard !isReadOnly else { return false }
        switch selection {
        case .insertionPoint(let offset):
            return lineRange.contains(offset) || offset == lineRange.upperBound
        case .ranges(let ranges):
            return ranges.contains { range in
                if range.isEmpty {
                    return lineRange.contains(range.lowerBound) || range.lowerBound == lineRange.upperBound
                }
                return range.overlaps(lineRange)
            }
        }
    }

    private func lineInfos(in text: AttributedString) -> [LineInfo] {
        var lines: [LineInfo] = []
        var startIndex = text.startIndex
        var currentIndex = text.startIndex
        var startOffset = 0
        var currentOffset = 0

        while currentIndex < text.endIndex {
            if text.characters[currentIndex].isNewline {
                let lineText = String(text[startIndex..<currentIndex].characters)
                lines.append(LineInfo(range: startOffset..<currentOffset, text: lineText))
                currentIndex = text.index(afterCharacter: currentIndex)
                currentOffset += 1
                startIndex = currentIndex
                startOffset = currentOffset
            } else {
                currentIndex = text.index(afterCharacter: currentIndex)
                currentOffset += 1
            }
        }

        let lineText = String(text[startIndex..<text.endIndex].characters)
        lines.append(LineInfo(range: startOffset..<currentOffset, text: lineText))
        return lines
    }

    private func paragraphStyle(for blockKind: BlockKind, listDepth: Int? = nil) -> NSParagraphStyle? {
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
            let depth = max(1, listDepth ?? 1)
            let listIndentUnit = em(1.5, fontSize: baseFontSize)
            let listIndent = listIndentUnit * CGFloat(depth)
            return paragraphStyle(
                lineSpacing: em(0.2, fontSize: baseFontSize),
                spacingBefore: 0,
                spacingAfter: 0,
                headIndent: listIndent
            )
        case .codeBlock:
            return paragraphStyle(
                lineSpacing: em(0.5, fontSize: inlineCodeFontSize),
                spacingBefore: 0,
                spacingAfter: 0,
                headIndent: DesignTokens.Spacing.md,
                tailIndent: DesignTokens.Spacing.md
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
        headIndent: CGFloat = 0,
        tailIndent: CGFloat = 0
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacingBefore = spacingBefore
        style.paragraphSpacing = spacingAfter
        style.headIndent = headIndent
        style.firstLineHeadIndent = headIndent
        if tailIndent != 0 {
            style.tailIndent = -tailIndent
        }
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
