import Foundation
import Combine
import LocalAuthentication

@MainActor
/// Observes biometric availability and state changes.
public final class BiometricMonitor: ObservableObject {
    @Published public private(set) var biometryType: LABiometryType = .none
    @Published public private(set) var isAvailable: Bool = false

    private var timer: Timer?

    public init() {
    }

    public func startMonitoring() {
        updateStatus()
        timer?.invalidate()
        let timer = Timer(
            timeInterval: 5.0,
            target: self,
            selector: #selector(handleTimerTick),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func updateStatus() {
        let context = LAContext()
        var error: NSError?
        isAvailable = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        biometryType = context.biometryType
    }

    @objc private func handleTimerTick() {
        updateStatus()
    }
}
