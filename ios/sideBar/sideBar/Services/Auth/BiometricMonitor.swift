import Foundation
import Combine
import LocalAuthentication
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Observes biometric availability and state changes.
@MainActor public final class BiometricMonitor: ObservableObject {
    @Published public private(set) var biometryType: LABiometryType = .none
    @Published public private(set) var isAvailable: Bool = false

    private let notificationCenter: NotificationCenter
    private let activeNotificationName: Notification.Name
    private let statusProvider: () -> (Bool, LABiometryType)
    private var activeObserver: NSObjectProtocol?

    public init() {
        self.notificationCenter = .default
        self.activeNotificationName = defaultBiometricMonitorActiveNotificationName()
        self.statusProvider = defaultBiometricMonitorStatusProvider
    }

    init(
        notificationCenter: NotificationCenter = .default,
        activeNotificationName: Notification.Name,
        statusProvider: @escaping () -> (Bool, LABiometryType)
    ) {
        self.notificationCenter = notificationCenter
        self.activeNotificationName = activeNotificationName
        self.statusProvider = statusProvider
    }

    public func startMonitoring() {
        refreshStatus()
        guard activeObserver == nil else {
            return
        }
        activeObserver = notificationCenter.addObserver(
            forName: activeNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshStatus()
            }
        }
    }

    public func stopMonitoring() {
        if let activeObserver {
            notificationCenter.removeObserver(activeObserver)
            self.activeObserver = nil
        }
    }

    deinit {
        if let activeObserver {
            notificationCenter.removeObserver(activeObserver)
        }
    }

    public func refreshStatus() {
        let status = statusProvider()
        isAvailable = status.0
        biometryType = status.1
    }
}

private func defaultBiometricMonitorStatusProvider() -> (Bool, LABiometryType) {
    let context = LAContext()
    var error: NSError?
    let available = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    return (available, context.biometryType)
}

private func defaultBiometricMonitorActiveNotificationName() -> Notification.Name {
    #if os(iOS)
    UIApplication.didBecomeActiveNotification
    #elseif os(macOS)
    NSApplication.didBecomeActiveNotification
    #else
    Notification.Name("BiometricMonitorDidBecomeActive")
    #endif
}
