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

    static func notification(_ type: NotificationType) {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(uiNotificationType(for: type))
        #endif
    }

    static func impact(_ style: ImpactStyle = .medium) {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: uiImpactStyle(for: style))
        generator.impactOccurred()
        #endif
    }

    static func selection() {
        #if os(iOS)
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
        #endif
    }

    #if os(iOS)
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
    #endif
}
