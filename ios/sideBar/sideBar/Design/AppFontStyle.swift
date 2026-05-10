import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum AppFontStyle {
    case displayLg
    case displayMd
    case titleLg
    case titleMd
    case titleSm
    case subheading
    case body
    case label
    case footnote
    case caption
    case badge
    case monoBody
    case monoLabel

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
        case .displayLg:
            return AppFontDefinition(fallbackSize: 32, weight: .regular)
        case .displayMd:
            return AppFontDefinition(fallbackSize: 24, weight: .bold)
        case .titleLg:
            return AppFontDefinition(
                fallbackSize: 22,
                textStyle: .title2,
                weight: .regular
            )
        case .titleMd:
            return AppFontDefinition(
                fallbackSize: 20,
                textStyle: .title3,
                weight: .bold
            )
        case .titleSm:
            return AppFontDefinition(fallbackSize: 18, weight: .bold)
        case .subheading:
            return AppFontDefinition(fallbackSize: 17, weight: .bold)
        case .body:
            return AppFontDefinition(
                fallbackSize: 16,
                textStyle: .body,
                weight: .regular
            )
        case .label:
            return AppFontDefinition(fallbackSize: 14, weight: .bold)
        case .footnote:
            return AppFontDefinition(
                fallbackSize: 13,
                textStyle: .footnote,
                weight: .regular
            )
        case .caption:
            return AppFontDefinition(
                fallbackSize: 12,
                textStyle: .caption,
                weight: .regular
            )
        case .badge:
            return AppFontDefinition(fallbackSize: 10, weight: .bold)
        case .monoBody:
            return AppFontDefinition(
                fallbackSize: 16,
                textStyle: .body,
                weight: .regular,
                design: .monospaced
            )
        case .monoLabel:
            return AppFontDefinition(
                fallbackSize: 14,
                weight: .bold,
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
            .body: UIFont.preferredFont(forTextStyle: .body).pointSize,
            .caption: UIFont.preferredFont(forTextStyle: .caption1).pointSize,
            .footnote: UIFont.preferredFont(forTextStyle: .footnote).pointSize
        ]
        return sizes[textStyle] ?? fallback
#elseif canImport(AppKit)
        let sizes: [Font.TextStyle: CGFloat] = [
            .title2: NSFont.preferredFont(forTextStyle: .title2).pointSize,
            .title3: NSFont.preferredFont(forTextStyle: .title3).pointSize,
            .body: NSFont.preferredFont(forTextStyle: .body).pointSize,
            .caption: NSFont.preferredFont(forTextStyle: .caption1).pointSize,
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
