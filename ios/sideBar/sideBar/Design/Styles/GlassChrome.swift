import SwiftUI

enum GlassChrome {
    enum Kind: Hashable {
        case pill
        case statusPill
        case metadataPill
        case card
        case largeCard
        case extraLargeCard
        case panelHeader
        case actionButton
        case field
        case popoverShell
        case modalShell
    }

    enum ShapeToken: Equatable {
        case capsule
        case roundedRectangle(cornerRadius: CGFloat)
    }

    enum MaterialToken: Equatable {
        case regular
        case interactive
    }

    enum FallbackFillToken: Equatable {
        case background
        case input
        case sidebar
        case surface

        var color: Color {
            switch self {
            case .background:
                return DesignTokens.Colors.background
            case .input:
                return DesignTokens.Colors.input
            case .sidebar:
                return DesignTokens.Colors.sidebar
            case .surface:
                return DesignTokens.Colors.surface
            }
        }
    }

    struct Tokens: Equatable {
        let shape: ShapeToken
        let material: MaterialToken
        let fallbackFill: FallbackFillToken
        let borderOpacity: Double
    }

    private static let tokenTable: [Kind: Tokens] = [
        .pill: Tokens(
            shape: .capsule,
            material: .interactive,
            fallbackFill: .surface,
            borderOpacity: 0.18
        ),
        .statusPill: Tokens(
            shape: .capsule,
            material: .regular,
            fallbackFill: .surface,
            borderOpacity: 0
        ),
        .metadataPill: Tokens(
            shape: .capsule,
            material: .regular,
            fallbackFill: .surface,
            borderOpacity: 1
        ),
        .card: Tokens(
            shape: .roundedRectangle(cornerRadius: DesignTokens.Radius.md),
            material: .regular,
            fallbackFill: .surface,
            borderOpacity: 1
        ),
        .largeCard: Tokens(
            shape: .roundedRectangle(cornerRadius: DesignTokens.Radius.lg),
            material: .regular,
            fallbackFill: .surface,
            borderOpacity: 0.18
        ),
        .extraLargeCard: Tokens(
            shape: .roundedRectangle(cornerRadius: DesignTokens.Radius.xl),
            material: .regular,
            fallbackFill: .surface,
            borderOpacity: 0.18
        ),
        .panelHeader: Tokens(
            shape: .roundedRectangle(cornerRadius: DesignTokens.Radius.sm),
            material: .regular,
            fallbackFill: .sidebar,
            borderOpacity: 0.18
        ),
        .actionButton: Tokens(
            shape: .roundedRectangle(cornerRadius: DesignTokens.Radius.sm),
            material: .interactive,
            fallbackFill: .surface,
            borderOpacity: 1
        ),
        .field: Tokens(
            shape: .roundedRectangle(cornerRadius: DesignTokens.Radius.sm),
            material: .regular,
            fallbackFill: .input,
            borderOpacity: 1
        ),
        .popoverShell: Tokens(
            shape: .roundedRectangle(cornerRadius: DesignTokens.Radius.lg),
            material: .regular,
            fallbackFill: .background,
            borderOpacity: 0.12
        ),
        .modalShell: Tokens(
            shape: .roundedRectangle(cornerRadius: DesignTokens.Radius.xl),
            material: .regular,
            fallbackFill: .background,
            borderOpacity: 0.12
        )
    ]

    static func tokens(for kind: Kind) -> Tokens {
        guard let tokens = tokenTable[kind] else {
            preconditionFailure("Missing glass chrome tokens for \(kind)")
        }
        return tokens
    }
}

private struct GlassChromeModifier: ViewModifier {
    let kind: GlassChrome.Kind

    func body(content: Content) -> some View {
        let tokens = GlassChrome.tokens(for: kind)

        Group {
            if #available(iOS 26.0, macOS 26.0, *) {
                glassEffect(content: content, tokens: tokens)
            } else {
                fallbackEffect(content: content, tokens: tokens)
            }
        }
    }

    @ViewBuilder
    private func glassEffect(content: Content, tokens: GlassChrome.Tokens) -> some View {
        switch (tokens.shape, tokens.material) {
        case (.capsule, .regular):
            content.glassEffect(.regular, in: Capsule())
        case (.capsule, .interactive):
            content.glassEffect(.regular.interactive(), in: Capsule())
        case (.roundedRectangle(let cornerRadius), .regular):
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        case (.roundedRectangle(let cornerRadius), .interactive):
            content
                .glassEffect(
                    .regular.interactive(),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
        }
    }

    @ViewBuilder
    private func fallbackEffect(content: Content, tokens: GlassChrome.Tokens) -> some View {
        switch tokens.shape {
        case .capsule:
            content
                .background(tokens.fallbackFill.color, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(DesignTokens.Colors.border.opacity(tokens.borderOpacity), lineWidth: 1)
                }
        case .roundedRectangle(let cornerRadius):
            content
                .background(
                    tokens.fallbackFill.color,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(DesignTokens.Colors.border.opacity(tokens.borderOpacity), lineWidth: 1)
                }
        }
    }
}

extension View {
    func glassChrome(_ kind: GlassChrome.Kind) -> some View {
        modifier(GlassChromeModifier(kind: kind))
    }
}
