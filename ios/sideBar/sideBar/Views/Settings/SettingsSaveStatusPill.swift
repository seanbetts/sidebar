import SwiftUI

enum SettingsSavePillState {
    case saving
    case saved
    case error
}

enum SettingsSaveStatusPillChrome: Equatable {
    case glass
    case material
}

enum SettingsSaveStatusPillPlatform {
    case iOS
    case macOS
}

struct SettingsSaveStatusPill: View {
    let state: SettingsSavePillState

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            switch state {
            case .saving:
                ProgressView()
                    .controlSize(.small)
                    .tint(.primary)
            case .saved:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.primary)
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(DesignTokens.Colors.error)
            }
            Text(title)
                .appFont(.labelMd)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.xsPlus)
        .modifier(SettingsSaveStatusPillBackgroundModifier(chrome: Self.chrome(for: currentPlatform)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }

    static func chrome(for platform: SettingsSaveStatusPillPlatform) -> SettingsSaveStatusPillChrome {
        switch platform {
        case .iOS:
            return .material
        case .macOS:
            return .glass
        }
    }

    private var title: String {
        switch state {
        case .saving:
            return "Saving settings..."
        case .saved:
            return "Saved"
        case .error:
            return "Couldn't save settings"
        }
    }

    private var currentPlatform: SettingsSaveStatusPillPlatform {
        #if os(iOS)
        .iOS
        #else
        .macOS
        #endif
    }
}

private struct SettingsSaveStatusPillBackgroundModifier: ViewModifier {
    let chrome: SettingsSaveStatusPillChrome

    func body(content: Content) -> some View {
        switch chrome {
        case .glass:
            content.glassEffect(.regular.interactive(), in: Capsule())
        case .material:
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                }
        }
    }
}
