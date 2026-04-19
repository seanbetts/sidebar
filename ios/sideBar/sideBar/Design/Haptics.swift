import SwiftUI
#if os(iOS)
import UIKit
#endif

enum Haptics {
    enum NotificationType {
        case success
        case warning
        case error
    }

    enum ImpactStyle {
        case light
        case medium
        case heavy
    }

    enum DeviceKind {
        case phone
        case pad
        case other
    }

    struct Client {
        let notification: (NotificationType) -> Void
        let impact: (ImpactStyle) -> Void
        let selection: () -> Void
    }

    private static var client = Client.live
    private static var isEnabled = { isSupported(on: currentDeviceKind()) }

    static func notification(_ type: NotificationType) {
        guard isEnabled() else { return }
        client.notification(type)
    }

    static func impact(_ style: ImpactStyle = .medium) {
        guard isEnabled() else { return }
        client.impact(style)
    }

    static func selection() {
        guard isEnabled() else { return }
        client.selection()
    }

    static func isSupported(on device: DeviceKind) -> Bool {
        switch device {
        case .phone:
            return true
        case .pad, .other:
            return false
        }
    }

    static func installTestingOverrides(
        client: Client? = nil,
        isEnabled: (() -> Bool)? = nil
    ) {
        if let client {
            self.client = client
        }
        if let isEnabled {
            self.isEnabled = isEnabled
        }
    }

    static func resetTestingOverrides() {
        client = .live
        isEnabled = { isSupported(on: currentDeviceKind()) }
    }

    private static func currentDeviceKind() -> DeviceKind {
        #if os(iOS)
        switch UIDevice.current.userInterfaceIdiom {
        case .phone:
            return .phone
        case .pad:
            return .pad
        default:
            return .other
        }
        #else
        return .other
        #endif
    }

    #if os(iOS)
    private static func makeLiveClient() -> Client {
        Client(
            notification: { type in
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(uiNotificationType(for: type))
            },
            impact: { style in
                let generator = UIImpactFeedbackGenerator(style: uiImpactStyle(for: style))
                generator.impactOccurred()
            },
            selection: {
                let generator = UISelectionFeedbackGenerator()
                generator.selectionChanged()
            }
        )
    }

    private static func uiNotificationType(for type: NotificationType) -> UINotificationFeedbackGenerator.FeedbackType {
        switch type {
        case .success:
            return .success
        case .warning:
            return .warning
        case .error:
            return .error
        }
    }

    private static func uiImpactStyle(for style: ImpactStyle) -> UIImpactFeedbackGenerator.FeedbackStyle {
        switch style {
        case .light:
            return .light
        case .medium:
            return .medium
        case .heavy:
            return .heavy
        }
    }
    #else
    private static func makeLiveClient() -> Client {
        Client(
            notification: { _ in },
            impact: { _ in },
            selection: {}
        )
    }
    #endif
}

private extension Haptics.Client {
    static var live: Self {
        Haptics.makeLiveClient()
    }
}
