import CoreFoundation
import Foundation

private final class WidgetIntentHandoffObservation {
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    func notify() {
        handler()
    }
}

private func widgetIntentHandoffCallback(
    center: CFNotificationCenter?,
    observer: UnsafeMutableRawPointer?,
    name: CFNotificationName?,
    object: UnsafeRawPointer?,
    userInfo: CFDictionary?
) {
    _ = center
    _ = name
    _ = object
    _ = userInfo
    guard let observer else { return }
    Unmanaged<WidgetIntentHandoffObservation>
        .fromOpaque(observer)
        .takeUnretainedValue()
        .notify()
}

/// Broadcasts queued widget action handoffs between extension and app processes.
public enum WidgetIntentHandoffNotifier {
    private static let notificationName = CFNotificationName(
        "ai.sidebar.sidebar.widget-intent-handoff" as CFString
    )

    /// Posts a cross-process widget intent handoff event.
    public static func post() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            notificationName,
            nil,
            nil,
            true
        )
    }

    /// Registers a callback for widget intent handoff events.
    public static func observe(_ handler: @escaping () -> Void) -> AnyObject {
        let observation = WidgetIntentHandoffObservation(handler: handler)
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(observation).toOpaque(),
            widgetIntentHandoffCallback,
            notificationName.rawValue,
            nil,
            .deliverImmediately
        )
        return observation
    }

    /// Removes a previously registered widget intent handoff observer.
    public static func removeObserver(_ token: AnyObject) {
        guard let observation = token as? WidgetIntentHandoffObservation else { return }
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(observation).toOpaque(),
            notificationName,
            nil
        )
    }
}
