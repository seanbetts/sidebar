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
    private static let bodyLineHeightMultiple: CGFloat = 1.7
    static let bodySpacingRem: CGFloat = 0.5

    private struct ParagraphStyleConfiguration {
        let fontSize: CGFloat
        let lineHeightMultiple: CGFloat
        let spacingBefore: CGFloat
        let spacingAfter: CGFloat
        let headIndent: CGFloat
        let tailIndent: CGFloat
    }

    static func bodyParagraphStyle(
        baseFontSize: CGFloat,
        headIndent: CGFloat = 0,
        tailIndent: CGFloat = 0
    ) -> NSParagraphStyle {
        paragraphStyle(
            configuration: ParagraphStyleConfiguration(
                fontSize: baseFontSize,
                lineHeightMultiple: bodyLineHeightMultiple,
                spacingBefore: bodySpacingRem * baseFontSize,
                spacingAfter: bodySpacingRem * baseFontSize,
                headIndent: headIndent,
                tailIndent: tailIndent
            )
        )
    }

    private static func paragraphStyle(
        configuration: ParagraphStyleConfiguration
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let desiredLineHeight = configuration.lineHeightMultiple * configuration.fontSize
        style.lineSpacing = max(0, desiredLineHeight - naturalLineHeight(for: configuration.fontSize))
        style.paragraphSpacingBefore = configuration.spacingBefore
        style.paragraphSpacing = configuration.spacingAfter
        style.headIndent = configuration.headIndent
        style.firstLineHeadIndent = configuration.headIndent
        if configuration.tailIndent != 0 {
            style.tailIndent = -configuration.tailIndent
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

enum NoteTextLayout {
    static let maxContentWidth: CGFloat = ContentLayout.maxContentWidth
    static let horizontalPadding: CGFloat = 20
    static let verticalPadding: CGFloat = 16
}
