import SwiftUI

enum SearchFieldChrome {
    case standard
    case dock
}

struct SearchField: View {
    @Binding var text: String
    @AppStorage(AppStorageKeys.appTextSize) private var appTextSizeRaw = AppTextSizeOption.system.rawValue
    var placeholder: String = "Search"
    var isFocused: FocusState<Bool>.Binding?
    var chrome: SearchFieldChrome = .standard

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: iconPointSize))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            if let isFocused {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .appFont(.body)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .focused(isFocused)
            } else {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .appFont(.body)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
            }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: iconPointSize))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .frame(minHeight: minHeight)
        .modifier(SearchFieldBackgroundModifier(chrome: Self.backgroundChrome(for: chrome)))
    }

    private var horizontalPadding: CGFloat {
        Self.horizontalPadding(for: chrome, option: resolvedTextSizeOption)
    }

    private var verticalPadding: CGFloat {
        Self.verticalPadding(for: chrome, option: resolvedTextSizeOption)
    }

    private var minHeight: CGFloat {
        Self.minHeight(for: chrome, option: resolvedTextSizeOption)
    }

    private var iconPointSize: CGFloat {
        AppFontStyle.subheadline.pointSize(for: resolvedTextSizeOption)
    }

    private var resolvedTextSizeOption: AppTextSizeOption {
        AppTextSizeOption.resolved(from: appTextSizeRaw)
    }

    static func backgroundChrome(for chrome: SearchFieldChrome) -> GlassChrome.Kind? {
        switch chrome {
        case .standard:
            return .field
        case .dock:
            return nil
        }
    }

    static func horizontalPadding(
        for chrome: SearchFieldChrome,
        option: AppTextSizeOption = .current
    ) -> CGFloat {
        let basePadding: CGFloat
        switch chrome {
        case .standard:
            basePadding = DesignTokens.Spacing.sm
        case .dock:
            basePadding = DesignTokens.Spacing.xs
        }
        return AppFontStyle.scaledMetric(basePadding, for: option)
    }

    static func verticalPadding(
        for chrome: SearchFieldChrome,
        option: AppTextSizeOption = .current
    ) -> CGFloat {
        switch chrome {
        case .standard, .dock:
            return AppFontStyle.scaledMetric(DesignTokens.Spacing.xxsPlus, for: option)
        }
    }

    static func minHeight(
        for chrome: SearchFieldChrome,
        option: AppTextSizeOption = .current
    ) -> CGFloat {
        switch chrome {
        case .standard, .dock:
            return AppFontStyle.scaledMetric(DesignTokens.Size.compactFieldHeight, for: option)
        }
    }
}

private struct SearchFieldBackgroundModifier: ViewModifier {
    let chrome: GlassChrome.Kind?

    func body(content: Content) -> some View {
        if let chrome {
            content.glassChrome(chrome)
        } else {
            content
        }
    }
}
