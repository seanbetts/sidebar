import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum AppFontStyle {
    case title3Semibold
    case titleLg
    case labelMd
    case body
    case headline
    case subheadline
    case subheadlineSemibold
    case callout
    case caption
    case captionSemibold
    case caption2
    case caption2Semibold
    case size18Semibold
    case size24Semibold

    func pointSize(for option: AppTextSizeOption) -> CGFloat {
        let definition = definition
        let baseSize: CGFloat
        if let textStyle = definition.textStyle {
            baseSize = AppFontMetrics.preferredPointSize(for: textStyle, fallback: definition.fallbackSize)
        } else {
            baseSize = definition.fallbackSize
        }
        return baseSize * option.scaleMultiplier
    }

    func font(for option: AppTextSizeOption) -> Font {
        let definition = definition
        return .system(
            size: pointSize(for: option),
            weight: definition.weight,
            design: definition.design
        )
    }
}

extension View {
    func appFont(_ style: AppFontStyle) -> some View {
        modifier(AppFontModifier(style: style))
    }
}

private extension AppFontStyle {
    var definition: AppFontDefinition {
        switch self {
        case .title3Semibold:
            return AppFontDefinition(
                fallbackSize: 20,
                textStyle: .title3,
                weight: .semibold
            )
        case .titleLg:
            return AppFontDefinition(fallbackSize: 18, weight: .semibold)
        case .labelMd:
            return AppFontDefinition(fallbackSize: 14, weight: .semibold)
        case .body:
            return AppFontDefinition(
                fallbackSize: 16,
                textStyle: .body,
                weight: .regular
            )
        case .headline:
            return AppFontDefinition(
                fallbackSize: 17,
                textStyle: .headline,
                weight: .regular
            )
        case .subheadline:
            return AppFontDefinition(
                fallbackSize: 15,
                textStyle: .subheadline,
                weight: .regular
            )
        case .subheadlineSemibold:
            return AppFontDefinition(
                fallbackSize: 15,
                textStyle: .subheadline,
                weight: .semibold
            )
        case .callout:
            return AppFontDefinition(
                fallbackSize: 16,
                textStyle: .callout,
                weight: .regular
            )
        case .caption:
            return AppFontDefinition(
                fallbackSize: 12,
                textStyle: .caption,
                weight: .regular
            )
        case .captionSemibold:
            return AppFontDefinition(
                fallbackSize: 12,
                textStyle: .caption,
                weight: .semibold
            )
        case .caption2:
            return AppFontDefinition(
                fallbackSize: 11,
                textStyle: .caption2,
                weight: .regular
            )
        case .caption2Semibold:
            return AppFontDefinition(
                fallbackSize: 11,
                textStyle: .caption2,
                weight: .semibold
            )
        case .size18Semibold:
            return AppFontDefinition(fallbackSize: 18, weight: .semibold)
        case .size24Semibold:
            return AppFontDefinition(fallbackSize: 24, weight: .semibold)
        }
    }
}

private struct AppFontDefinition {
    let fallbackSize: CGFloat
    let textStyle: Font.TextStyle?
    let weight: Font.Weight
    let design: Font.Design

    init(
        fallbackSize: CGFloat,
        textStyle: Font.TextStyle? = nil,
        weight: Font.Weight,
        design: Font.Design = .default
    ) {
        self.fallbackSize = fallbackSize
        self.textStyle = textStyle
        self.weight = weight
        self.design = design
    }
}

private enum AppFontMetrics {
    static func preferredPointSize(for textStyle: Font.TextStyle, fallback: CGFloat) -> CGFloat {
#if canImport(UIKit)
        let sizes: [Font.TextStyle: CGFloat] = [
            .title2: UIFont.preferredFont(forTextStyle: .title2).pointSize,
            .title3: UIFont.preferredFont(forTextStyle: .title3).pointSize,
            .headline: UIFont.preferredFont(forTextStyle: .headline).pointSize,
            .subheadline: UIFont.preferredFont(forTextStyle: .subheadline).pointSize,
            .callout: UIFont.preferredFont(forTextStyle: .callout).pointSize,
            .body: UIFont.preferredFont(forTextStyle: .body).pointSize,
            .caption: UIFont.preferredFont(forTextStyle: .caption1).pointSize,
            .caption2: UIFont.preferredFont(forTextStyle: .caption2).pointSize,
            .footnote: UIFont.preferredFont(forTextStyle: .footnote).pointSize
        ]
        return sizes[textStyle] ?? fallback
#elseif canImport(AppKit)
        let sizes: [Font.TextStyle: CGFloat] = [
            .title2: NSFont.preferredFont(forTextStyle: .title2).pointSize,
            .title3: NSFont.preferredFont(forTextStyle: .title3).pointSize,
            .headline: NSFont.preferredFont(forTextStyle: .headline).pointSize,
            .subheadline: NSFont.preferredFont(forTextStyle: .subheadline).pointSize,
            .callout: NSFont.preferredFont(forTextStyle: .callout).pointSize,
            .body: NSFont.preferredFont(forTextStyle: .body).pointSize,
            .caption: NSFont.preferredFont(forTextStyle: .caption1).pointSize,
            .caption2: NSFont.preferredFont(forTextStyle: .caption2).pointSize,
            .footnote: NSFont.preferredFont(forTextStyle: .footnote).pointSize
        ]
        return sizes[textStyle] ?? fallback
#else
        return fallback
#endif
    }
}

private struct AppFontModifier: ViewModifier {
    let style: AppFontStyle
    @AppStorage(AppStorageKeys.appTextSize) private var appTextSizeRaw = AppTextSizeOption.system.rawValue

    func body(content: Content) -> some View {
        let option = AppTextSizeOption.resolved(from: appTextSizeRaw)
        content.font(style.font(for: option))
    }
}
