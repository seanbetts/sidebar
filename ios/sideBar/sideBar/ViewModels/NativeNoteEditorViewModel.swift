@preconcurrency import Foundation
import Combine
import SwiftUI
#if os(iOS)
@preconcurrency import UIKit
#elseif os(macOS)
@preconcurrency import AppKit
#endif

@MainActor
@available(iOS 26.0, macOS 26.0, *)
/// View model for editing and styling native note content.
public final class NativeNoteEditorViewModel: ObservableObject {
    static let noteStyle = NoteTextStyle.default

    @Published public var attributedContent: AttributedString = AttributedString()
    @Published public var selection: AttributedTextSelection = AttributedTextSelection()
    @Published public var isReadOnly: Bool = false
    @Published public internal(set) var hasUnsavedChanges: Bool = false
    @Published public internal(set) var autosaveToken: Int = 0
    public var autosaveDelay: TimeInterval = 1.5

#if os(iOS)
    typealias PlatformFont = UIFont
    typealias PlatformFontWeight = UIFont.Weight
    typealias PlatformColor = UIColor
#elseif os(macOS)
    typealias PlatformFont = NSFont
    typealias PlatformFontWeight = NSFont.Weight
    typealias PlatformColor = NSColor
#endif

    var baseFontSize: CGFloat = NoteTextTypography.defaultBodyFontSize
    var inlineCodeFontSize: CGFloat {
        NoteTextTypography.inlineCodeFontSize(baseFontSize: baseFontSize)
    }
    var bodyFont: Font {
        Font.system(size: baseFontSize)
    }
    var inlineCodeFont: Font {
        Font.system(size: inlineCodeFontSize, weight: .regular, design: .monospaced)
    }
    var blockCodeFont: Font {
        Font.system(size: inlineCodeFontSize, weight: .regular, design: .monospaced)
    }
    var lastSavedContent: String = ""
    var lastSavedCanonicalContent: String = ""
    var autosaveTask: Task<Void, Never>?
    var isUpdatingPrefixVisibility = false
    var usesInjectedListMarkers = false
    var prefixRefreshTask: Task<Void, Never>?
    var pendingPrefixRefreshScope: PrefixRefreshScope?
    var lastHandledContentSourceGeneration: Int = 0
    var lastHandledSelectionSourceGeneration: Int = 0
    var lastSelectionLineSpan: ClosedRange<Int>?
    var plainTextRuntimeModeEnabled: Bool = false

    public init() {}

    public func setBaseFontSize(_ size: CGFloat) {
        let updatedSize = max(12, size)
        guard abs(baseFontSize - updatedSize) > 0.1 else { return }
        baseFontSize = updatedSize
        normalizeDocumentStylingForDisplay()
    }

    public func currentPlainText() -> String {
        String(attributedContent.characters)
    }

    func defaultTypingAttributes(
        blockKind: BlockKind = .paragraph,
        listDepth: Int? = nil
    ) -> AttributeContainer {
        var attrs = AttributeContainer()
        attrs.blockKind = blockKind
        attrs.listDepth = listDepth
        attrs.codeLanguage = nil
        setFont(baseFont(for: blockKind), platformFont: platformBaseFont(for: blockKind), in: &attrs)
        setForegroundColor(baseForegroundColor(for: blockKind), in: &attrs)
        setBackgroundColor(baseBackgroundColor(for: blockKind), in: &attrs)
        attrs.paragraphStyle = paragraphStyle(for: blockKind, listDepth: listDepth)
        attrs[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = typingPresentationIntent(
            blockKind: blockKind,
            listDepth: listDepth
        )
        attrs[AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = listDelimiter(for: blockKind)
        attrs.strikethroughStyle = blockKind == .taskChecked ? .single : nil
        return attrs
    }

    func contextualTypingFallbackAttributes() -> AttributeContainer {
        guard !attributedContent.characters.isEmpty else {
            return defaultTypingAttributes()
        }
        guard let paragraphRange = selectedParagraphRanges().first, !paragraphRange.isEmpty else {
            return defaultTypingAttributes()
        }

        let blockKind = attributedContent[paragraphRange].blockKind
            ?? attributedContent.blockKind(in: paragraphRange)
            ?? .paragraph
        let listDepth: Int? = isListBlockKind(blockKind)
            ? max(1, attributedContent[paragraphRange].listDepth ?? 1)
            : nil
        return defaultTypingAttributes(blockKind: blockKind, listDepth: listDepth)
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
        transformSelectionAttributes { attrs in
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

    public func applyFormatting(_ formatting: NoteFormatting) {
        guard !isReadOnly, !plainTextRuntimeModeEnabled else { return }
        let previousContent = attributedContent
        let previousSelection = selection
        AttributedNoteFormattingCommands.apply(formatting, on: self)
        guard attributedContent != previousContent || selection != previousSelection else { return }

        if !hasUnsavedChanges {
            hasUnsavedChanges = true
        }
        let currentSelectionSpan = selectionLineSpan(in: attributedContent)
        requestPrefixRefresh(scope: .lineSpan(unionLineSpan(lastSelectionLineSpan, currentSelectionSpan)))
        scheduleAutosave()
        lastSelectionLineSpan = currentSelectionSpan
    }

    public func handleContentChange(previous: AttributedString) {
        handleContentChange(previous: previous, sourceGeneration: nil)
    }

    public func handleContentChange(previous: AttributedString, sourceGeneration: Int?) {
        guard !isReadOnly else { return }
        if let sourceGeneration {
            guard sourceGeneration > lastHandledContentSourceGeneration else { return }
            lastHandledContentSourceGeneration = sourceGeneration
        }
        guard attributedContent != previous else { return }

        if plainTextRuntimeModeEnabled {
            normalizeCurrentContentForPlainTextRuntime()
        } else {
            var normalizedContent = attributedContent
            stripUnsupportedInlineStyles(in: &normalizedContent)
            if applyDetectedLinks(in: &normalizedContent) || normalizedContent != attributedContent {
                if attributedContent != normalizedContent {
                    attributedContent = normalizedContent
                }
            }
        }

        // Mark dirty immediately so close/switch flows can prompt even before autosave fires.
        if !hasUnsavedChanges {
            hasUnsavedChanges = true
        }
        scheduleAutosave()
        lastSelectionLineSpan = selectionLineSpan(in: attributedContent)
    }

    public func handleSelectionChange() {
        handleSelectionChange(sourceGeneration: nil)
    }

    public func handleSelectionChange(sourceGeneration: Int?) {
        guard !isReadOnly else { return }
        if let sourceGeneration {
            guard sourceGeneration > lastHandledSelectionSourceGeneration else { return }
            lastHandledSelectionSourceGeneration = sourceGeneration
        }
        lastSelectionLineSpan = selectionLineSpan(in: attributedContent)
    }

    func hasInlineIntent(_ intent: InlinePresentationIntent) -> Bool {
        let nonEmptyRanges = selectionRanges().ranges.filter { !$0.isEmpty }
        if !nonEmptyRanges.isEmpty {
            return nonEmptyRanges.allSatisfy { range in
                let runs = attributedContent[range].runs
                guard !runs.isEmpty else { return false }
                return runs.allSatisfy { run in
                    (run.inlinePresentationIntent ?? []).contains(intent)
                }
            }
        }

        let attrs = selection.typingAttributes(in: attributedContent)
        if (attrs.inlinePresentationIntent ?? []).contains(intent) {
            return true
        }

        switch selection.indices(in: attributedContent) {
        case .insertionPoint(let index):
            guard index > attributedContent.startIndex else { return false }
            let previous = attributedContent.index(beforeCharacter: index)
            let previousRange = previous..<index
            return (attributedContent[previousRange].inlinePresentationIntent ?? []).contains(intent)
        case .ranges(let ranges):
            for range in ranges.ranges where range.isEmpty {
                guard range.lowerBound > attributedContent.startIndex else { return false }
                let previous = attributedContent.index(beforeCharacter: range.lowerBound)
                let previousRange = previous..<range.lowerBound
                return (attributedContent[previousRange].inlinePresentationIntent ?? []).contains(intent)
            }
            return false
        }
    }

    func applyInlineIntent(
        _ intent: InlinePresentationIntent,
        enabled: Bool,
        range: Range<AttributedString.Index>? = nil
    ) {
        if let range {
            applyInlineIntentToRange(intent, enabled: enabled, range: range)
            return
        }
        transformSelectionAttributes { attrs in
            updateInlineIntent(intent, enabled: enabled, attrs: &attrs)
        }
    }

    func updateInlineIntent(
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
                setBackgroundColor(Self.noteStyle.codeBackground, in: &attrs)
            } else {
                setFont(baseFont(for: blockKind), platformFont: platformBaseFont(for: blockKind), in: &attrs)
                setForegroundColor(baseForegroundColor(for: blockKind), in: &attrs)
                setBackgroundColor(baseBackgroundColor(for: blockKind), in: &attrs)
            }
        }
    }

    func applyInlineIntentToRange(
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
            setBackgroundColor(Self.noteStyle.codeBackground, in: &attributedContent, range: range)
        } else {
            let blockKind = attributedContent.blockKind(in: range)
            setFont(baseFont(for: blockKind), platformFont: platformBaseFont(for: blockKind), in: &attributedContent, range: range)
            setForegroundColor(baseForegroundColor(for: blockKind), in: &attributedContent, range: range)
            setBackgroundColor(baseBackgroundColor(for: blockKind), in: &attributedContent, range: range)
        }
    }

    func applyBlockStyle(blockKind: BlockKind, range: Range<AttributedString.Index>) {
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
            setStrikethrough(true, in: &attributedContent, range: range)
            setForegroundColor(DesignTokens.Colors.textSecondary, in: &attributedContent, range: range)
        } else if blockKind == .taskUnchecked {
            setStrikethrough(false, in: &attributedContent, range: range)
            setForegroundColor(baseForegroundColor(for: blockKind), in: &attributedContent, range: range)
        }
    }

    func applyPresentationIntent(
        blockKind: BlockKind,
        listDepth: Int?,
        range: Range<AttributedString.Index>
    ) {
        if let headingLevel = headingLevel(for: blockKind) {
            applyHeadingIntent(level: headingLevel, range: range)
            return
        }
        if applyListIntent(blockKind: blockKind, listDepth: listDepth, range: range) {
            return
        }
        switch blockKind {
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6:
            return
        case .bulletList, .orderedList, .taskChecked, .taskUnchecked:
            return
        case .blockquote:
            let quoteIntent = PresentationIntent(.blockQuote, identity: 1)
            attributedContent[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
                .paragraph,
                identity: 1,
                parent: quoteIntent
            )
        case .codeBlock:
            let languageHint = attributedContent[range].codeLanguage
            attributedContent[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
                .codeBlock(languageHint: languageHint),
                identity: 1
            )
        case .horizontalRule:
            attributedContent[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
                .thematicBreak,
                identity: 1
            )
        case .paragraph, .blankLine, .imageCaption, .gallery, .htmlBlock:
            attributedContent[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
                .paragraph,
                identity: 1
            )
        @unknown default:
            return
        }
    }

    func headingLevel(for blockKind: BlockKind) -> Int? {
        switch blockKind {
        case .heading1: return 1
        case .heading2: return 2
        case .heading3: return 3
        case .heading4: return 4
        case .heading5: return 5
        case .heading6: return 6
        default: return nil
        }
    }

    func applyHeadingIntent(level: Int, range: Range<AttributedString.Index>) {
        attributedContent[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
            .header(level: level),
            identity: level
        )
    }

    func applyListIntent(
        blockKind: BlockKind,
        listDepth: Int?,
        range: Range<AttributedString.Index>
    ) -> Bool {
        guard blockKind == .bulletList
            || blockKind == .orderedList
            || blockKind == .taskChecked
            || blockKind == .taskUnchecked
        else { return false }
        let listKind: PresentationIntent.Kind = blockKind == .orderedList ? .orderedList : .unorderedList
        let listId = listDepth ?? 1
        let listIntent = PresentationIntent(listKind, identity: listId)
        let listItemIntent = PresentationIntent(
            .listItem(ordinal: 1),
            identity: listId * 1000 + 1,
            parent: listIntent
        )
        attributedContent[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
            .paragraph,
            identity: 1,
            parent: listItemIntent
        )
        attributedContent[range][AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = listDelimiter(for: blockKind)
        return true
    }

    func listDelimiter(for blockKind: BlockKind) -> Character? {
        switch blockKind {
        case .bulletList:
            return "•"
        case .taskChecked:
            return "☑"
        case .taskUnchecked:
            return "☐"
        default:
            return nil
        }
    }

}
