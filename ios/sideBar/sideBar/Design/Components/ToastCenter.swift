import SwiftUI
import Combine

@MainActor
public final class ToastCenter: ObservableObject {
    @Published public private(set) var toast: ToastMessage?
    private var dismissTask: Task<Void, Never>?

    public func show(message: String, style: ToastStyle = .error, duration: TimeInterval = 2.5) {
        dismissTask?.cancel()
        let toast = ToastMessage(message: message, style: style)
        self.toast = toast
        Haptics.notification(style.hapticType)
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            await MainActor.run {
                if self?.toast?.id == toast.id {
                    self?.toast = nil
                }
            }
        }
    }

    public func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        toast = nil
    }
}

public struct ToastMessage: Identifiable, Equatable {
    public let id = UUID()
    public let message: String
    public let style: ToastStyle
}

public enum ToastStyle {
    case error
    case success

    public var background: Color {
        switch self {
        case .error:
            return DesignTokens.Colors.errorSurface
        case .success:
            return DesignTokens.Colors.successBackground
        }
    }

    public var foreground: Color {
        switch self {
        case .error:
            return DesignTokens.Colors.error
        case .success:
            return DesignTokens.Colors.success
        }
    }

    public var border: Color {
        switch self {
        case .error:
            return DesignTokens.Colors.errorBorder
        case .success:
            return DesignTokens.Colors.successBorder
        }
    }

    public var iconName: String {
        switch self {
        case .error:
            return "exclamationmark.triangle.fill"
        case .success:
            return "checkmark.circle"
        }
    }

    var hapticType: Haptics.NotificationType {
        switch self {
        case .error:
            return .error
        case .success:
            return .success
        }
    }
}

public struct ToastBanner: View {
    public let toast: ToastMessage

    public init(toast: ToastMessage) {
        self.toast = toast
    }

    public var body: some View {
        HStack(spacing: DesignTokens.Spacing.xsPlus) {
            iconView
            Text(toast.message)
                .appFont(.subheading)
                .lineLimit(2)
        }
        .foregroundStyle(toast.style.foreground)
        .padding(.vertical, DesignTokens.Spacing.xsPlus)
        .padding(.horizontal, DesignTokens.Spacing.md)
        .modifier(ToastBannerChromeModifier())
        .overlay(
            Capsule()
                .stroke(toast.style.border, lineWidth: 1)
        )
        .appShadow(color: Color.black.opacity(0.08), radius: DesignTokens.Spacing.xs, y: DesignTokens.Spacing.xxs)
        .accessibilityLabel(toast.message)
    }

    @ViewBuilder
    private var iconView: some View {
        Image(systemName: toast.style.iconName)
            .appFont(.labelMd)
    }
}

private struct ToastBannerChromeModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content.background(.ultraThinMaterial, in: Capsule())
        }
    }
}
