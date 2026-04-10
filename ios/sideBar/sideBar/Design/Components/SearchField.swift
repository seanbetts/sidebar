import SwiftUI

enum SearchFieldChrome {
    case standard
    case dock
}

struct SearchField: View {
    @Binding var text: String
    var placeholder: String = "Search"
    var isFocused: FocusState<Bool>.Binding?
    var chrome: SearchFieldChrome = .standard

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            if let isFocused {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .appFont(.subheadline)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .focused(isFocused)
            } else {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .appFont(.subheadline)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
            }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
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
        Self.horizontalPadding(for: chrome)
    }

    private var verticalPadding: CGFloat {
        Self.verticalPadding(for: chrome)
    }

    private var minHeight: CGFloat {
        Self.minHeight(for: chrome)
    }

    static func backgroundChrome(for chrome: SearchFieldChrome) -> GlassChrome.Kind? {
        switch chrome {
        case .standard:
            return .field
        case .dock:
            return nil
        }
    }

    static func horizontalPadding(for chrome: SearchFieldChrome) -> CGFloat {
        switch chrome {
        case .standard:
            DesignTokens.Spacing.sm
        case .dock:
            DesignTokens.Spacing.xs
        }
    }

    static func verticalPadding(for chrome: SearchFieldChrome) -> CGFloat {
        switch chrome {
        case .standard, .dock:
            DesignTokens.Spacing.xxsPlus
        }
    }

    static func minHeight(for chrome: SearchFieldChrome) -> CGFloat {
        switch chrome {
        case .standard, .dock:
            DesignTokens.Size.compactFieldHeight
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
