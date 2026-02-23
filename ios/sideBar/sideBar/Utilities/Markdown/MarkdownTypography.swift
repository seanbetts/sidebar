import CoreGraphics
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum MarkdownTypography {
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
    static let inlineCodeScale: CGFloat = 0.875
    private static let fallbackFootnoteScale: CGFloat = 13.0 / 16.0

    static func inlineCodeFontSize(baseFontSize: CGFloat) -> CGFloat {
        baseFontSize * inlineCodeScale
    }

    static func footnoteFontSize(baseFontSize: CGFloat) -> CGFloat {
        baseFontSize * footnoteScale
    }

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
