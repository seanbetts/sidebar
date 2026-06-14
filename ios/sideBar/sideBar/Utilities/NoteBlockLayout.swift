import Foundation
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
struct NoteBlockLayoutContext {
    let baseFontSize: CGFloat
    let previousBlockType: NotesSemanticDocument.BlockType?
    let nextBlockType: NotesSemanticDocument.BlockType?
    let additionalSpacingBefore: CGFloat
    let additionalSpacingAfter: CGFloat

    init(
        baseFontSize: CGFloat,
        previousBlockType: NotesSemanticDocument.BlockType? = nil,
        nextBlockType: NotesSemanticDocument.BlockType? = nil,
        additionalSpacingBefore: CGFloat = 0,
        additionalSpacingAfter: CGFloat = 0
    ) {
        self.baseFontSize = baseFontSize
        self.previousBlockType = previousBlockType
        self.nextBlockType = nextBlockType
        self.additionalSpacingBefore = additionalSpacingBefore
        self.additionalSpacingAfter = additionalSpacingAfter
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct NoteBlockLayoutMetrics {
    let lineSpacing: CGFloat
    let spacingBefore: CGFloat
    let spacingAfter: CGFloat
    let headIndent: CGFloat
    let firstLineHeadIndent: CGFloat
    let tailIndent: CGFloat
    let tabStops: [NSTextTab]
    let defaultTabInterval: CGFloat
}

@available(iOS 26.0, macOS 26.0, *)
enum NoteBlockLayout {
    static func metrics(
        for blockType: NotesSemanticDocument.BlockType,
        context: NoteBlockLayoutContext
    ) -> NoteBlockLayoutMetrics {
        let base = baseMetrics(for: blockType, baseFontSize: context.baseFontSize)
        return NoteBlockLayoutMetrics(
            lineSpacing: base.lineSpacing,
            spacingBefore: base.spacingBefore
                + adjacencySpacingBefore(for: blockType, previousBlockType: context.previousBlockType)
                + context.additionalSpacingBefore,
            spacingAfter: base.spacingAfter
                + adjacencySpacingAfter(for: blockType, nextBlockType: context.nextBlockType)
                + context.additionalSpacingAfter,
            headIndent: base.headIndent,
            firstLineHeadIndent: base.firstLineHeadIndent,
            tailIndent: base.tailIndent,
            tabStops: base.tabStops,
            defaultTabInterval: base.defaultTabInterval
        )
    }

    static func paragraphStyle(
        for blockType: NotesSemanticDocument.BlockType,
        context: NoteBlockLayoutContext,
        includesBlockSpacing: Bool = true
    ) -> NSParagraphStyle {
        let resolvedMetrics = metrics(for: blockType, context: context)
        return paragraphStyle(
            metrics: includesBlockSpacing
                ? resolvedMetrics
                : contentMetrics(from: resolvedMetrics, for: blockType)
        )
    }

    static func paragraphStyle(metrics: NoteBlockLayoutMetrics) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = metrics.lineSpacing
        style.paragraphSpacingBefore = metrics.spacingBefore
        style.paragraphSpacing = metrics.spacingAfter
        style.headIndent = metrics.headIndent
        style.firstLineHeadIndent = metrics.firstLineHeadIndent
        if metrics.tailIndent != 0 {
            style.tailIndent = -metrics.tailIndent
        }
        style.tabStops = metrics.tabStops
        style.defaultTabInterval = metrics.defaultTabInterval
        return style
    }

    static func codeBlockPaddingBefore(baseFontSize _: CGFloat) -> CGFloat { 6 }

    static func codeBlockPaddingAfter(baseFontSize _: CGFloat) -> CGFloat { 12 }

    static func codeBlockMarginBefore(baseFontSize _: CGFloat) -> CGFloat { 8 }

    static func codeBlockMarginAfter(baseFontSize _: CGFloat) -> CGFloat { 8 }

    static func orderedListContentIndent(baseFontSize: CGFloat) -> CGFloat {
        baseFontSize * 2.5
    }

    static func orderedListMarkerIndent(baseFontSize: CGFloat) -> CGFloat {
        baseFontSize
    }

    private static func baseMetrics(
        for blockType: NotesSemanticDocument.BlockType,
        baseFontSize: CGFloat
    ) -> NoteBlockLayoutMetrics {
        switch blockType {
        case .title:
            return plainMetrics(spacingBefore: 0, spacingAfter: baseFontSize * 0.25)
        case .paragraph:
            return plainMetrics(spacingBefore: 0, spacingAfter: 4)
        case .heading:
            return plainMetrics(
                spacingBefore: baseFontSize * 0.75,
                spacingAfter: baseFontSize * 0.1875
            )
        case .subheading:
            return plainMetrics(
                spacingBefore: baseFontSize * 0.5,
                spacingAfter: baseFontSize * 0.125
            )
        case .unorderedList, .checklist:
            return plainMetrics(
                headIndent: baseFontSize,
                firstLineHeadIndent: baseFontSize
            )
        case .orderedList:
            let contentIndent = orderedListContentIndent(baseFontSize: baseFontSize)
            let markerIndent = orderedListMarkerIndent(baseFontSize: baseFontSize)
            return plainMetrics(
                headIndent: contentIndent,
                firstLineHeadIndent: markerIndent,
                tabStops: [NSTextTab(textAlignment: .left, location: contentIndent)],
                defaultTabInterval: contentIndent
            )
        case .blockquote:
            let indent = baseFontSize * 1.25
            return plainMetrics(
                spacingBefore: 8,
                spacingAfter: 8,
                headIndent: indent,
                firstLineHeadIndent: indent
            )
        case .codeBlock:
            let inset = baseFontSize * 0.75
            return plainMetrics(
                spacingBefore: codeBlockMarginBefore(baseFontSize: baseFontSize),
                spacingAfter: codeBlockMarginAfter(baseFontSize: baseFontSize),
                headIndent: inset,
                firstLineHeadIndent: inset,
                tailIndent: inset
            )
        case .listItem,
             .table,
             .tableRow,
             .tableCell,
             .media,
             .caption,
             .htmlBlock:
            return plainMetrics()
        }
    }

    private static func plainMetrics(
        spacingBefore: CGFloat = 0,
        spacingAfter: CGFloat = 0,
        headIndent: CGFloat = 0,
        firstLineHeadIndent: CGFloat? = nil,
        tailIndent: CGFloat = 0,
        tabStops: [NSTextTab] = [],
        defaultTabInterval: CGFloat = 0
    ) -> NoteBlockLayoutMetrics {
        NoteBlockLayoutMetrics(
            lineSpacing: 0,
            spacingBefore: spacingBefore,
            spacingAfter: spacingAfter,
            headIndent: headIndent,
            firstLineHeadIndent: firstLineHeadIndent ?? headIndent,
            tailIndent: tailIndent,
            tabStops: tabStops,
            defaultTabInterval: defaultTabInterval
        )
    }

    private static func contentMetrics(
        from metrics: NoteBlockLayoutMetrics,
        for blockType: NotesSemanticDocument.BlockType
    ) -> NoteBlockLayoutMetrics {
        guard blockType == .codeBlock else { return metrics }

        return NoteBlockLayoutMetrics(
            lineSpacing: metrics.lineSpacing,
            spacingBefore: 0,
            spacingAfter: 0,
            headIndent: metrics.headIndent,
            firstLineHeadIndent: metrics.firstLineHeadIndent,
            tailIndent: metrics.tailIndent,
            tabStops: metrics.tabStops,
            defaultTabInterval: metrics.defaultTabInterval
        )
    }

    private static func adjacencySpacingBefore(
        for blockType: NotesSemanticDocument.BlockType,
        previousBlockType: NotesSemanticDocument.BlockType?
    ) -> CGFloat {
        guard blockType != .codeBlock, previousBlockType == .codeBlock else { return 0 }
        return codeBlockPaddingAfter(baseFontSize: 0) + codeBlockMarginAfter(baseFontSize: 0)
    }

    private static func adjacencySpacingAfter(
        for blockType: NotesSemanticDocument.BlockType,
        nextBlockType: NotesSemanticDocument.BlockType?
    ) -> CGFloat {
        var spacing: CGFloat = 0
        if isListBlockType(blockType), nextBlockType != blockType {
            spacing += 4
        }
        if blockType != .codeBlock, nextBlockType == .codeBlock {
            spacing += codeBlockPaddingBefore(baseFontSize: 0) + codeBlockMarginBefore(baseFontSize: 0)
        }
        return spacing
    }

    private static func isListBlockType(_ blockType: NotesSemanticDocument.BlockType) -> Bool {
        switch blockType {
        case .unorderedList, .orderedList, .checklist:
            return true
        case .title,
             .paragraph,
             .heading,
             .subheading,
             .listItem,
             .blockquote,
             .codeBlock,
             .table,
             .tableRow,
             .tableCell,
             .media,
             .caption,
             .htmlBlock:
            return false
        }
    }
}
