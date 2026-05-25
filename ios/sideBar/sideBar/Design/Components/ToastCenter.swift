import SwiftUI
import Combine

@MainActor
public final class ToastCenter: ObservableObject {
    @Published public private(set) var toast: ToastMessage?
    private var dismissTask: Task<Void, Never>?
    private let sleep: @MainActor @Sendable (UInt64) async -> Void

    public init(
        sleep: @escaping @MainActor @Sendable (UInt64) async -> Void = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.sleep = sleep
    }

    public func show(message: String, style: ToastStyle = .error, duration: TimeInterval = 2.5) {
        dismissTask?.cancel()
        let toast = ToastMessage(message: message, style: style)
        let sleep = self.sleep
        self.toast = toast
        Haptics.notification(style.hapticType)
        dismissTask = Task { [weak self, sleep] in
            await sleep(UInt64(duration * 1_000_000_000))
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

    var statusPillTone: StatusPillTone {
        switch self {
        case .error:
            return .error
        case .success:
            return .success
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
        StatusPill(
            title: toast.message,
            tone: toast.style.statusPillTone,
            style: .banner,
            accessibilityLabel: toast.message
        )
        .appShadow(
            color: Color.black.opacity(0.08),
            radius: DesignTokens.Spacing.xs,
            y: DesignTokens.Spacing.xxs
        )
    }
}
