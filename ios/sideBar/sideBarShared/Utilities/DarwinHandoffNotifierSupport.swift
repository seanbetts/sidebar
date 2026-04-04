import CoreFoundation
import Foundation

final class DarwinHandoffObserver {
    private let handler: () -> Void
    private var localObserver: NSObjectProtocol?

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    func startObservingLocalNotifications(named name: Notification.Name) {
        localObserver = NotificationCenter.default.addObserver(
            forName: name,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.notify()
        }
    }

    func stopObservingLocalNotifications() {
        guard let localObserver else { return }
        NotificationCenter.default.removeObserver(localObserver)
        self.localObserver = nil
    }

    func notify() {
        handler()
    }
}

func darwinHandoffCallback(
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
    Unmanaged<DarwinHandoffObserver>
        .fromOpaque(observer)
        .takeUnretainedValue()
        .notify()
}

enum DarwinHandoffNotifierSupport {
    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static func post(
        darwinNotificationName: CFNotificationName,
        localNotificationName: Notification.Name
    ) {
        if isRunningUnitTests {
            NotificationCenter.default.post(name: localNotificationName, object: nil)
            return
        }

        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            darwinNotificationName,
            nil,
            nil,
            true
        )
    }

    static func observe(
        darwinNotificationName: CFNotificationName,
        localNotificationName: Notification.Name,
        handler: @escaping () -> Void
    ) -> AnyObject {
        let observation = DarwinHandoffObserver(handler: handler)

        if isRunningUnitTests {
            observation.startObservingLocalNotifications(named: localNotificationName)
        } else {
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                Unmanaged.passUnretained(observation).toOpaque(),
                darwinHandoffCallback,
                darwinNotificationName.rawValue,
                nil,
                .deliverImmediately
            )
        }

        return observation
    }

    static func removeObserver(
        _ token: AnyObject,
        darwinNotificationName: CFNotificationName
    ) {
        guard let observation = token as? DarwinHandoffObserver else { return }

        if isRunningUnitTests {
            observation.stopObservingLocalNotifications()
        } else {
            CFNotificationCenterRemoveObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                Unmanaged.passUnretained(observation).toOpaque(),
                darwinNotificationName,
                nil
            )
        }
    }
}
