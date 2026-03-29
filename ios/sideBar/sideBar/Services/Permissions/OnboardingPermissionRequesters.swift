import CoreLocation
import Foundation
import UserNotifications
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
/// Provides onboarding-specific access to the current location permission state.
public protocol LocationPermissionRequesting: AnyObject {
    var currentState: OnboardingPermissionState { get }
    func requestPermission() async -> OnboardingPermissionState
}

@MainActor
/// Provides onboarding-specific access to the current notifications permission state.
public protocol NotificationPermissionRequesting: AnyObject {
    func currentState() async -> OnboardingPermissionState
    func requestPermission() async -> OnboardingPermissionState
}

@MainActor
/// Requests and maps the system location permission for onboarding.
public final class LocationPermissionRequester: NSObject, LocationPermissionRequesting {
    private let manager: CLLocationManager
    private var continuation: CheckedContinuation<OnboardingPermissionState, Never>?

    public var currentState: OnboardingPermissionState {
        Self.map(manager.authorizationStatus)
    }

    public init(manager: CLLocationManager = CLLocationManager()) {
        self.manager = manager
        super.init()
        self.manager.delegate = self
    }

    public func requestPermission() async -> OnboardingPermissionState {
        let state = currentState
        guard state == .notAsked else { return state }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    private func finishRequest(with state: OnboardingPermissionState) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: state)
    }

    private static func map(_ status: CLAuthorizationStatus) -> OnboardingPermissionState {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            return .granted
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notAsked
        @unknown default:
            return .denied
        }
    }
}

extension LocationPermissionRequester: CLLocationManagerDelegate {
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let state = Self.map(manager.authorizationStatus)
        guard state != .notAsked else { return }
        finishRequest(with: state)
    }

    public func locationManager(
        _ manager: CLLocationManager,
        didChangeAuthorization status: CLAuthorizationStatus
    ) {
        let state = Self.map(status)
        guard state != .notAsked else { return }
        finishRequest(with: state)
    }
}

@MainActor
/// Requests and maps the system notifications permission for onboarding.
public final class NotificationPermissionRequester: NotificationPermissionRequesting {
    private let center: UNUserNotificationCenter
    private let requestOptions: UNAuthorizationOptions
    private let registerForRemoteNotifications: @MainActor @Sendable () -> Void

    public init(
        center: UNUserNotificationCenter = .current(),
        requestOptions: UNAuthorizationOptions = [.badge],
        registerForRemoteNotifications: @escaping @MainActor @Sendable () -> Void = {
#if os(iOS)
#if targetEnvironment(simulator)
            return
#else
            UIApplication.shared.registerForRemoteNotifications()
#endif
#elseif os(macOS)
            NSApplication.shared.registerForRemoteNotifications()
#endif
        }
    ) {
        self.center = center
        self.requestOptions = requestOptions
        self.registerForRemoteNotifications = registerForRemoteNotifications
    }

    public func currentState() async -> OnboardingPermissionState {
        let status = await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
        return Self.map(status)
    }

    public func requestPermission() async -> OnboardingPermissionState {
        let state = await currentState()
        guard state == .notAsked else {
            if state == .granted {
                registerForRemoteNotifications()
            }
            return state
        }

        let isGranted = await withCheckedContinuation { continuation in
            center.requestAuthorization(options: requestOptions) { granted, _ in
                continuation.resume(returning: granted)
            }
        }

        if isGranted {
            registerForRemoteNotifications()
            return .granted
        }

        let updatedState = await currentState()
        return updatedState == .notAsked ? .denied : updatedState
    }

    private static func map(_ status: UNAuthorizationStatus) -> OnboardingPermissionState {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return .granted
        case .denied:
            return .denied
        case .notDetermined:
            return .notAsked
        @unknown default:
            return .denied
        }
    }
}
