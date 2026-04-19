import Foundation

/// Result of the most recent push registration attempt.
public enum PushRegistrationResult: String, Codable, Equatable {
    case success
    case failure
}

/// Device-local push lifecycle state exposed to diagnostics.
public struct PushLifecycleDiagnosticsState: Equatable {
    /// The current device installation id.
    public let currentDeviceInstallationId: String?
    /// Redacted APNs token suffix for the current device.
    public let currentDeviceTokenSuffix: String?
    /// The last registration attempt start time.
    public let lastDeviceRegistrationAttemptAt: Date?
    /// The last registration attempt result.
    public let lastDeviceRegistrationResult: PushRegistrationResult?
    /// The last presence update time.
    public let lastDevicePresenceUpdateAt: Date?
    /// The most recent foreground/background value reported for presence.
    public let currentDevicePresenceIsForeground: Bool?

    public init(
        currentDeviceInstallationId: String? = nil,
        currentDeviceTokenSuffix: String? = nil,
        lastDeviceRegistrationAttemptAt: Date? = nil,
        lastDeviceRegistrationResult: PushRegistrationResult? = nil,
        lastDevicePresenceUpdateAt: Date? = nil,
        currentDevicePresenceIsForeground: Bool? = nil
    ) {
        self.currentDeviceInstallationId = currentDeviceInstallationId
        self.currentDeviceTokenSuffix = currentDeviceTokenSuffix
        self.lastDeviceRegistrationAttemptAt = lastDeviceRegistrationAttemptAt
        self.lastDeviceRegistrationResult = lastDeviceRegistrationResult
        self.lastDevicePresenceUpdateAt = lastDevicePresenceUpdateAt
        self.currentDevicePresenceIsForeground = currentDevicePresenceIsForeground
    }

    func updating(
        currentDeviceInstallationId: String? = nil,
        currentDeviceTokenSuffix: String? = nil,
        lastDeviceRegistrationAttemptAt: Date? = nil,
        lastDeviceRegistrationResult: PushRegistrationResult? = nil,
        lastDevicePresenceUpdateAt: Date? = nil,
        currentDevicePresenceIsForeground: Bool? = nil
    ) -> Self {
        Self(
            currentDeviceInstallationId: currentDeviceInstallationId ?? self.currentDeviceInstallationId,
            currentDeviceTokenSuffix: currentDeviceTokenSuffix ?? self.currentDeviceTokenSuffix,
            lastDeviceRegistrationAttemptAt: lastDeviceRegistrationAttemptAt ?? self.lastDeviceRegistrationAttemptAt,
            lastDeviceRegistrationResult: lastDeviceRegistrationResult ?? self.lastDeviceRegistrationResult,
            lastDevicePresenceUpdateAt: lastDevicePresenceUpdateAt ?? self.lastDevicePresenceUpdateAt,
            currentDevicePresenceIsForeground: currentDevicePresenceIsForeground ?? self.currentDevicePresenceIsForeground
        )
    }
}

/// Summary of the current account for internal diagnostics.
public struct NotificationDiagnosticsAccountSummary: Codable, Equatable {
    /// The user id owning the diagnostics view.
    public let userId: String
}

/// Installation row returned by the internal diagnostics snapshot.
public struct NotificationDiagnosticsInstallationRow: Codable, Equatable {
    /// The stable installation id.
    public let installationId: String
    /// The owning user id.
    public let userId: String
    /// The client platform, such as `ios` or `macos`.
    public let platform: String
    /// Redacted token suffix for quick correlation.
    public let tokenSuffix: String?
    /// Whether the app reported foreground presence at the time of the snapshot.
    public let isForeground: Bool?
}

/// Delivery audit row returned by the internal diagnostics snapshot.
public struct NotificationDiagnosticsDeliveryAuditRow: Codable, Equatable {
    /// When the delivery event was recorded.
    public let createdAt: String
    /// The owning user id.
    public let userId: String
    /// The installation that was targeted, when available.
    public let installationId: String?
    /// The notification kind associated with the delivery attempt.
    public let notificationKind: String
    /// The client platform, when available.
    public let platform: String?
    /// Redacted token suffix for correlation.
    public let tokenSuffix: String?
    /// The recorded delivery outcome.
    public let deliveryResult: String
    /// Optional skip reason for non-delivery events.
    public let skipReason: String?
    /// APNs status code for rejected requests.
    public let apnsStatusCode: Int?
    /// APNs reason string for rejected requests.
    public let apnsReason: String?
    /// APNs topic for accepted or rejected requests.
    public let apnsTopic: String?
    /// APNs environment associated with the request.
    public let apnsEnvironment: String?
}

/// Response body for the signed-in diagnostics snapshot endpoint.
public struct InternalNotificationDiagnosticsSnapshot: Codable, Equatable {
    /// Capability flag returned by the backend.
    public let canAccessInternalDiagnostics: Bool
    /// Current account summary.
    public let accountSummary: NotificationDiagnosticsAccountSummary?
    /// Active installations owned by the current user.
    public let installations: [NotificationDiagnosticsInstallationRow]
    /// Recent delivery audit rows, newest first.
    public let recentDelivery: [NotificationDiagnosticsDeliveryAuditRow]
}

/// Response body returned after sending a test push.
public struct InternalNotificationTestPushResponse: Codable, Equatable {
    /// The targeted installation id.
    public let installationId: String
    /// Whether the test push was accepted by APNs.
    public let accepted: Bool
    /// Optional human-readable detail from the backend.
    public let message: String?
}
