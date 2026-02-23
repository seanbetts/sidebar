import SwiftUI

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

    var font: Font {
        switch self {
        case .title3Semibold:
            return DesignTokens.Typography.title3Semibold
        case .titleLg:
            return DesignTokens.Typography.titleLg
        case .labelMd:
            return DesignTokens.Typography.labelMd
        case .body:
            return DesignTokens.Typography.body
        case .headline:
            return DesignTokens.Typography.headline
        case .subheadline:
            return DesignTokens.Typography.subheadline
        case .subheadlineSemibold:
            return DesignTokens.Typography.subheadlineSemibold
        case .callout:
            return DesignTokens.Typography.callout
        case .caption:
            return DesignTokens.Typography.caption
        case .captionSemibold:
            return DesignTokens.Typography.captionSemibold
        case .caption2:
            return DesignTokens.Typography.caption2
        case .caption2Semibold:
            return DesignTokens.Typography.caption2Semibold
        case .size18Semibold:
            return .system(size: 18 * AppTextSizeOption.currentScaleMultiplier, weight: .semibold)
        case .size24Semibold:
            return .system(size: 24 * AppTextSizeOption.currentScaleMultiplier, weight: .semibold)
        }
    }
}

extension View {
    func appFont(_ style: AppFontStyle) -> some View {
        font(style.font)
    }
}
