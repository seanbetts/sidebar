import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum NoteTextTypography {
    static var defaultBodyFontSize: CGFloat {
        defaultBodyFontSize(for: AppTextSizeOption.resolved(
            from: UserDefaults.standard.string(forKey: AppStorageKeys.appTextSize)
                ?? AppTextSizeOption.system.rawValue
        ))
    }

    static func defaultBodyFontSize(for option: AppTextSizeOption) -> CGFloat {
        baseBodyFontSize * option.scaleMultiplier
    }

    private static var baseBodyFontSize: CGFloat {
#if canImport(UIKit)
        UIFont.preferredFont(forTextStyle: .body).pointSize
#elseif canImport(AppKit)
        NSFont.preferredFont(forTextStyle: .body).pointSize
#else
        16
#endif
    }
}

@available(iOS 26.0, macOS 26.0, *)
enum NoteTextParagraphMetrics {
    static func codeBlockPaddingBefore(baseFontSize: CGFloat) -> CGFloat {
        6
    }

    static func codeBlockPaddingAfter(baseFontSize: CGFloat) -> CGFloat {
        12
    }

    static func orderedListContentIndent(baseFontSize: CGFloat) -> CGFloat {
        baseFontSize * 2.5
    }

    static func orderedListMarkerIndent(baseFontSize: CGFloat) -> CGFloat {
        baseFontSize
    }

    private struct StyleMetrics {
        let lineSpacing: CGFloat
        let spacingBefore: CGFloat
        let spacingAfter: CGFloat
    }

    private struct ParagraphStyleConfiguration {
        let lineSpacing: CGFloat
        let spacingBefore: CGFloat
        let spacingAfter: CGFloat
        let headIndent: CGFloat
        let firstLineHeadIndent: CGFloat
        let tailIndent: CGFloat
        let tabStops: [NSTextTab]
        let defaultTabInterval: CGFloat
    }

    static func bodyParagraphStyle(
        baseFontSize: CGFloat,
        headIndent: CGFloat = 0,
        tailIndent: CGFloat = 0
    ) -> NSParagraphStyle {
        return paragraphStyle(
            for: .paragraph,
            baseFontSize: baseFontSize,
            headIndent: headIndent,
            tailIndent: tailIndent
        )
    }

    static func paragraphStyle(
        for blockType: NotesSemanticDocument.BlockType,
        baseFontSize: CGFloat,
        additionalSpacingBefore: CGFloat = 0,
        additionalSpacingAfter: CGFloat = 0,
        headIndent: CGFloat = 0,
        firstLineHeadIndent: CGFloat? = nil,
        tailIndent: CGFloat = 0,
        tabStops: [NSTextTab] = [],
        defaultTabInterval: CGFloat = 0
    ) -> NSParagraphStyle {
        let metrics = styleMetrics(for: blockType, baseFontSize: baseFontSize)
        return paragraphStyle(
            configuration: ParagraphStyleConfiguration(
                lineSpacing: metrics.lineSpacing,
                spacingBefore: metrics.spacingBefore + additionalSpacingBefore,
                spacingAfter: metrics.spacingAfter + additionalSpacingAfter,
                headIndent: headIndent,
                firstLineHeadIndent: firstLineHeadIndent ?? headIndent,
                tailIndent: tailIndent,
                tabStops: tabStops,
                defaultTabInterval: defaultTabInterval
            )
        )
    }

    static func boundaryParagraphStyle(
        after previousBlockType: NotesSemanticDocument.BlockType?,
        before nextBlockType: NotesSemanticDocument.BlockType,
        baseFontSize: CGFloat
    ) -> NSParagraphStyle {
        paragraphStyle(
            configuration: ParagraphStyleConfiguration(
                lineSpacing: 0,
                spacingBefore: nextBlockType == .codeBlock
                    ? codeBlockPaddingBefore(baseFontSize: baseFontSize)
                    : 0,
                spacingAfter: previousBlockType == .codeBlock
                    ? codeBlockPaddingAfter(baseFontSize: baseFontSize)
                    : 0,
                headIndent: 0,
                firstLineHeadIndent: 0,
                tailIndent: 0,
                tabStops: [],
                defaultTabInterval: 0
            )
        )
    }

    private static func paragraphStyle(
        configuration: ParagraphStyleConfiguration
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = configuration.lineSpacing
        style.paragraphSpacingBefore = configuration.spacingBefore
        style.paragraphSpacing = configuration.spacingAfter
        style.headIndent = configuration.headIndent
        style.firstLineHeadIndent = configuration.firstLineHeadIndent
        if configuration.tailIndent != 0 {
            style.tailIndent = -configuration.tailIndent
        }
        style.tabStops = configuration.tabStops
        style.defaultTabInterval = configuration.defaultTabInterval
        return style
    }

    private static func styleMetrics(
        for blockType: NotesSemanticDocument.BlockType,
        baseFontSize: CGFloat
    ) -> StyleMetrics {
        if let style = NoteTextStyle(blockType: blockType) {
            switch style {
            case .title:
                return StyleMetrics(
                    lineSpacing: 0,
                    spacingBefore: 0,
                    spacingAfter: baseFontSize * 0.25
                )
            case .heading:
                return StyleMetrics(
                    lineSpacing: 0,
                    spacingBefore: baseFontSize * 0.75,
                    spacingAfter: baseFontSize * 0.1875
                )
            case .subheading:
                return StyleMetrics(
                    lineSpacing: 0,
                    spacingBefore: baseFontSize * 0.5,
                    spacingAfter: baseFontSize * 0.125
                )
            case .body:
                return StyleMetrics(lineSpacing: 0, spacingBefore: 0, spacingAfter: 4)
            }
        }

        switch blockType {
        case .unorderedList, .orderedList, .checklist, .listItem, .blockquote, .codeBlock:
            return StyleMetrics(lineSpacing: 0, spacingBefore: 0, spacingAfter: 0)
        case .table, .tableRow, .tableCell, .media, .caption, .htmlBlock:
            return StyleMetrics(lineSpacing: 0, spacingBefore: 0, spacingAfter: 0)
        case .title, .paragraph, .heading, .subheading:
            return StyleMetrics(lineSpacing: 0, spacingBefore: 0, spacingAfter: 0)
        }
    }
}

enum NoteTextLayout {
    static let maxContentWidth: CGFloat = ContentLayout.maxContentWidth
    static let horizontalPadding: CGFloat = 20
    static let verticalPadding: CGFloat = 16
}
