import SwiftUI

struct SkillSymbolIcon: View {
    let systemName: String
    let font: Font
    let foreground: Color

    init(
        systemName: String,
        font: Font = .subheadline,
        foreground: Color = DesignTokens.Colors.textSecondary
    ) {
        self.systemName = systemName
        self.font = font
        self.foreground = foreground
    }

    var body: some View {
        Image(systemName: systemName)
            .font(font)
            .foregroundStyle(foreground)
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
                font: .system(size: iconSize, weight: .medium),
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
