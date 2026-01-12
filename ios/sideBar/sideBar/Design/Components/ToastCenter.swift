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
            return Color.red.opacity(0.12)
        }
    }

    public var foreground: Color {
        switch self {
        case .error:
            return Color.red
        }
    }
}

public struct ToastBanner: View {
    public let toast: ToastMessage

    public init(toast: ToastMessage) {
        self.toast = toast
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
            Text(toast.message)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
        }
        .foregroundStyle(toast.style.foreground)
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(toast.style.background)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.red.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
        .accessibilityLabel(toast.message)
    }
}
