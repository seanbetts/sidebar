import CoreFoundation
import Foundation

private final class WidgetTaskCompletionHandoffObservation {
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    func notify() {
        handler()
    }
}

private func widgetTaskCompletionHandoffCallback(
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
    Unmanaged<WidgetTaskCompletionHandoffObservation>
        .fromOpaque(observer)
        .takeUnretainedValue()
        .notify()
}

/// Broadcasts widget task completions between extension and app processes.
public enum WidgetTaskCompletionHandoffNotifier {
    private static let notificationName = CFNotificationName(
        "ai.sidebar.sidebar.widget-task-completion-handoff" as CFString
    )

    /// Posts a cross-process widget task completion event.
    public static func post() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            notificationName,
            nil,
            nil,
            true
        )
    }

    /// Registers a callback for widget task completion events.
    public static func observe(_ handler: @escaping () -> Void) -> AnyObject {
        let observation = WidgetTaskCompletionHandoffObservation(handler: handler)
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(observation).toOpaque(),
            widgetTaskCompletionHandoffCallback,
            notificationName.rawValue,
            nil,
            .deliverImmediately
        )
        return observation
    }

    /// Removes a previously registered task completion observer.
    public static func removeObserver(_ token: AnyObject) {
        guard let observation = token as? WidgetTaskCompletionHandoffObservation else { return }
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(observation).toOpaque(),
            notificationName,
            nil
        )
    }
}
