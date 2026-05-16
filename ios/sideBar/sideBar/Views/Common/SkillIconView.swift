import sideBarShared
import SwiftUI

struct SkillSymbolIcon: View {
    let icon: AppIcon
    let appFontStyle: AppFontStyle?
    let pointSize: CGFloat?
    let weight: Font.Weight
    let design: Font.Design
    let foreground: Color

    init(
        systemName: String,
        appFontStyle: AppFontStyle = .subheading,
        foreground: Color = DesignTokens.Colors.textSecondary
    ) {
        self.icon = AppIcon(rawValue: systemName)
        self.appFontStyle = appFontStyle
        self.pointSize = nil
        self.weight = .regular
        self.design = .default
        self.foreground = foreground
    }

    init(
        appIcon: AppIcon,
        appFontStyle: AppFontStyle = .subheading,
        foreground: Color = DesignTokens.Colors.textSecondary
    ) {
        self.icon = appIcon
        self.appFontStyle = appFontStyle
        self.pointSize = nil
        self.weight = .regular
        self.design = .default
        self.foreground = foreground
    }

    init(
        systemName: String,
        pointSize: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        foreground: Color = DesignTokens.Colors.textSecondary
    ) {
        self.icon = AppIcon(rawValue: systemName)
        self.appFontStyle = nil
        self.pointSize = pointSize
        self.weight = weight
        self.design = design
        self.foreground = foreground
    }

    init(
        appIcon: AppIcon,
        pointSize: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        foreground: Color = DesignTokens.Colors.textSecondary
    ) {
        self.icon = appIcon
        self.appFontStyle = nil
        self.pointSize = pointSize
        self.weight = weight
        self.design = design
        self.foreground = foreground
    }

    @ViewBuilder
    var body: some View {
        if let appFontStyle {
            Image(appIcon: icon)
                .appFont(appFontStyle)
                .foregroundStyle(foreground)
        } else {
            Image(appIcon: icon)
                .appScaledFont(
                    size: pointSize ?? AppFontStyle.subheading.pointSize(for: .system),
                    weight: weight,
                    design: design
                )
                .foregroundStyle(foreground)
        }
    }
}

struct SkillAppIcon: View {
    let systemName: String
    var size: CGFloat = 62
    var cornerRadius: CGFloat = 16
    var iconSize: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white)
            SkillSymbolIcon(
                systemName: systemName,
                pointSize: iconSize,
                weight: .medium,
                foreground: Color.black.opacity(0.75)
            )
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(DesignTokens.Colors.border, lineWidth: 1)
        )
    }
}
