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

    static func inlineCodeFontSize(baseFontSize: CGFloat) -> CGFloat {
        baseFontSize * inlineCodeScale
    }

    static func footnoteFontSize(baseFontSize: CGFloat) -> CGFloat {
        baseFontSize * footnoteScale
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

    private static let inlineCodeScale: CGFloat = 0.875
    private static let fallbackFootnoteScale: CGFloat = 13.0 / 16.0

    private static var footnoteScale: CGFloat {
#if canImport(UIKit)
        let bodySize = UIFont.preferredFont(forTextStyle: .body).pointSize
        let footnoteSize = UIFont.preferredFont(forTextStyle: .footnote).pointSize
#elseif canImport(AppKit)
        let bodySize = NSFont.preferredFont(forTextStyle: .body).pointSize
        let footnoteSize = NSFont.preferredFont(forTextStyle: .footnote).pointSize
#else
        let bodySize = CGFloat.zero
        let footnoteSize = CGFloat.zero
#endif
        guard bodySize > 0, footnoteSize > 0 else {
            return fallbackFootnoteScale
        }
        return footnoteSize / bodySize
    }
}

@available(iOS 26.0, macOS 26.0, *)
enum NoteTextParagraphMetrics {
    private static let bodyLineHeightMultiple: CGFloat = 1.7
    static let bodySpacingRem: CGFloat = 0.5

    static func bodyParagraphStyle(
        baseFontSize: CGFloat,
        headIndent: CGFloat = 0,
        tailIndent: CGFloat = 0
    ) -> NSParagraphStyle {
        paragraphStyle(
            fontSize: baseFontSize,
            lineHeightMultiple: bodyLineHeightMultiple,
            spacingBefore: bodySpacingRem * baseFontSize,
            spacingAfter: bodySpacingRem * baseFontSize,
            headIndent: headIndent,
            tailIndent: tailIndent
        )
    }

    private static func paragraphStyle(
        fontSize: CGFloat,
        lineHeightMultiple: CGFloat,
        spacingBefore: CGFloat,
        spacingAfter: CGFloat,
        headIndent: CGFloat,
        tailIndent: CGFloat
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let desiredLineHeight = lineHeightMultiple * fontSize
        style.lineSpacing = max(0, desiredLineHeight - naturalLineHeight(for: fontSize))
        style.paragraphSpacingBefore = spacingBefore
        style.paragraphSpacing = spacingAfter
        style.headIndent = headIndent
        style.firstLineHeadIndent = headIndent
        if tailIndent != 0 {
            style.tailIndent = -tailIndent
        }
        return style
    }

    private static func naturalLineHeight(for fontSize: CGFloat) -> CGFloat {
#if canImport(UIKit)
        return UIFont.systemFont(ofSize: fontSize, weight: .regular).lineHeight
#elseif canImport(AppKit)
        let font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
        return font.ascender - font.descender + font.leading
#else
        return fontSize
#endif
    }
}

struct NoteTextStyle: Equatable {
    let codeBackground: Color
    let codeBlockBackground: Color

    static let `default` = NoteTextStyle(
        codeBackground: DesignTokens.Colors.muted,
        codeBlockBackground: DesignTokens.Colors.muted
    )
}

enum NoteTextLayout {
    static let maxContentWidth: CGFloat = ContentLayout.maxContentWidth
    static let horizontalPadding: CGFloat = 20
    static let verticalPadding: CGFloat = 16
}
