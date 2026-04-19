import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum AppFontStyle {
    case title2
    case title2Semibold
    case title3Semibold
    case titleLg
    case size16Semibold
    case labelMd
    case body
    case bodySemibold
    case headline
    case subheading
    case subheadline
    case subheadlineSemibold
    case callout
    case footnote
    case footnoteSemibold
    case caption
    case captionSemibold
    case caption2
    case caption2Semibold
    case size10Bold
    case size18Semibold
    case size24Semibold
    case size32Regular
    case size32Semibold
    case monoLabel
    case monoBody

    func pointSize(for option: AppTextSizeOption) -> CGFloat {
        let definition = definition
        let baseSize: CGFloat
        if let textStyle = definition.textStyle {
            baseSize = AppFontMetrics.preferredPointSize(for: textStyle, fallback: definition.fallbackSize)
        } else {
            baseSize = definition.fallbackSize
        }
        return Self.scaledPointSize(baseSize, for: option)
    }

    func font(for option: AppTextSizeOption) -> Font {
        let definition = definition
        return .system(
            size: pointSize(for: option),
            weight: definition.weight,
            design: definition.design
        )
    }

    static func scaledPointSize(_ baseSize: CGFloat, for option: AppTextSizeOption) -> CGFloat {
        baseSize * option.scaleMultiplier
    }

    static func scaledMetric(_ baseSize: CGFloat, for option: AppTextSizeOption) -> CGFloat {
        let systemBodyPointSize = body.pointSize(for: .system)
        guard systemBodyPointSize > 0 else {
            return baseSize
        }

        let metricScale = body.pointSize(for: option) / systemBodyPointSize
        return baseSize * metricScale
    }
}

extension View {
    func appFont(_ style: AppFontStyle) -> some View {
        modifier(AppFontModifier(style: style))
    }

    func appScaledFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> some View {
        modifier(
            AppScaledFontModifier(
                size: size,
                weight: weight,
                design: design
            )
        )
    }
}

private extension AppFontStyle {
    var definition: AppFontDefinition {
        switch self {
        case .title2:
            return AppFontDefinition(
                fallbackSize: 22,
                textStyle: .title2,
                weight: .regular
            )
        case .title2Semibold:
            return AppFontDefinition(
                fallbackSize: 22,
                textStyle: .title2,
                weight: .semibold
            )
        case .title3Semibold:
            return AppFontDefinition(
                fallbackSize: 20,
                textStyle: .title3,
                weight: .semibold
            )
        case .titleLg:
            return AppFontDefinition(fallbackSize: 18, weight: .semibold)
        case .size16Semibold:
            return AppFontDefinition(fallbackSize: 16, weight: .semibold)
        case .labelMd:
            return AppFontDefinition(fallbackSize: 14, weight: .semibold)
        case .body:
            return AppFontDefinition(
                fallbackSize: 16,
                textStyle: .body,
                weight: .regular
            )
        case .bodySemibold:
            return AppFontDefinition(
                fallbackSize: 16,
                textStyle: .body,
                weight: .semibold
            )
        case .headline:
            return AppFontDefinition(
                fallbackSize: 17,
                textStyle: .headline,
                weight: .regular
            )
        case .subheading:
            return AppFontDefinition(
                fallbackSize: 15,
                textStyle: .subheadline,
                weight: .semibold
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
        case .footnote:
            return AppFontDefinition(
                fallbackSize: 13,
                textStyle: .footnote,
                weight: .regular
            )
        case .footnoteSemibold:
            return AppFontDefinition(
                fallbackSize: 13,
                textStyle: .footnote,
                weight: .semibold
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
        case .size10Bold:
            return AppFontDefinition(fallbackSize: 10, weight: .bold)
        case .size18Semibold:
            return AppFontDefinition(fallbackSize: 18, weight: .semibold)
        case .size24Semibold:
            return AppFontDefinition(fallbackSize: 24, weight: .semibold)
        case .size32Regular:
            return AppFontDefinition(fallbackSize: 32, weight: .regular)
        case .size32Semibold:
            return AppFontDefinition(fallbackSize: 32, weight: .semibold)
        case .monoLabel:
            return AppFontDefinition(
                fallbackSize: 14,
                weight: .semibold,
                design: .monospaced
            )
        case .monoBody:
            return AppFontDefinition(
                fallbackSize: 16,
                textStyle: .body,
                weight: .regular,
                design: .monospaced
            )
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

private struct AppScaledFontModifier: ViewModifier {
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    @AppStorage(AppStorageKeys.appTextSize) private var appTextSizeRaw = AppTextSizeOption.system.rawValue

    func body(content: Content) -> some View {
        let option = AppTextSizeOption.resolved(from: appTextSizeRaw)
        content.font(
            .system(
                size: AppFontStyle.scaledPointSize(size, for: option),
                weight: weight,
                design: design
            )
        )
    }
}
