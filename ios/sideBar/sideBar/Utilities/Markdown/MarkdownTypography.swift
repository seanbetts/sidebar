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

    static func inlineCodeFontSize(baseFontSize: CGFloat) -> CGFloat {
        baseFontSize * inlineCodeScale
    }
}
