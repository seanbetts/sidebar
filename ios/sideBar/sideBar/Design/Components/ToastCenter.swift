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

    public var background: Color {
        switch self {
        case .error:
            return DesignTokens.Colors.errorSurface
        }
    }

    public var foreground: Color {
        switch self {
        case .error:
            return DesignTokens.Colors.error
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
            Image(systemName: "exclamationmark.triangle.fill")
                .font(DesignTokens.Typography.labelMd)
            Text(toast.message)
                .font(DesignTokens.Typography.subheadlineSemibold)
                .lineLimit(2)
        }
        .foregroundStyle(toast.style.foreground)
        .padding(.vertical, DesignTokens.Spacing.xsPlus)
        .padding(.horizontal, DesignTokens.Spacing.md)
        .background(toast.style.background)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(DesignTokens.Colors.errorBorder, lineWidth: 1)
        )
        .appShadow(color: Color.black.opacity(0.08), radius: DesignTokens.Spacing.xs, y: DesignTokens.Spacing.xxs)
        .accessibilityLabel(toast.message)
    }
}
