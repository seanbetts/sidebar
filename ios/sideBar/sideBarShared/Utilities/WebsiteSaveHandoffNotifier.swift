import CoreFoundation
import Foundation

private final class WebsiteSaveHandoffObservation {
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    func notify() {
        handler()
    }
}

private func websiteSaveHandoffCallback(
    center: CFNotificationCenter?,
    observer: UnsafeMutableRawPointer?,
    name: CFNotificationName?,
    object: UnsafeRawPointer?,
    userInfo: CFDictionary?
) {
    guard let observer else { return }
    Unmanaged<WebsiteSaveHandoffObservation>
        .fromOpaque(observer)
        .takeUnretainedValue()
        .notify()
}

/// Broadcasts website-save handoff changes between Apple app and extension processes.
public enum WebsiteSaveHandoffNotifier {
    private static let notificationName = CFNotificationName("ai.sidebar.sidebar.website-save-handoff" as CFString)

    /// Posts a cross-process website-save handoff event.
    public static func post() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            notificationName,
            nil,
            nil,
            true
        )
    }

    /// Registers a callback for cross-process website-save handoff events.
    public static func observe(_ handler: @escaping () -> Void) -> AnyObject {
        let observation = WebsiteSaveHandoffObservation(handler: handler)
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(observation).toOpaque(),
            websiteSaveHandoffCallback,
            notificationName.rawValue,
            nil,
            .deliverImmediately
        )
        return observation
    }

    /// Removes a previously registered website-save handoff observer.
    public static func removeObserver(_ token: AnyObject) {
        guard let observation = token as? WebsiteSaveHandoffObservation else { return }
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(observation).toOpaque(),
            notificationName,
            nil
        )
    }
}
