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
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous))
        .overlay(borderOverlay)
    }

    private var horizontalPadding: CGFloat {
        switch chrome {
        case .standard:
            DesignTokens.Spacing.sm
        case .dock:
            DesignTokens.Spacing.xs
        }
    }

    private var verticalPadding: CGFloat {
        switch chrome {
        case .standard:
            DesignTokens.Spacing.xs
        case .dock:
            DesignTokens.Spacing.xxs
        }
    }

    private var backgroundColor: Color {
        switch chrome {
        case .standard:
            DesignTokens.Colors.input
        case .dock:
            .clear
        }
    }

    @ViewBuilder
    private var borderOverlay: some View {
        switch chrome {
        case .standard:
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                .stroke(DesignTokens.Colors.border, lineWidth: 1)
        case .dock:
            EmptyView()
        }
    }
}
