import Foundation
import SwiftUI

@MainActor
final class DevicePresenceReporter {
    typealias SendPresenceUpdate = @MainActor @Sendable (String, Bool, String?) async -> Void

    private let throttleInterval: TimeInterval
    private let now: () -> Date
    private let sendPresenceUpdate: SendPresenceUpdate
    private let timestampFormatter: ISO8601DateFormatter
    private var lastReportedToken: String?
    private var lastReportedForeground: Bool?
    private var lastReportedAt: Date?
    private(set) var currentIsForeground = false

    init(
        throttleInterval: TimeInterval = 30,
        now: @escaping () -> Date = Date.init,
        sendPresenceUpdate: @escaping SendPresenceUpdate
    ) {
        self.throttleInterval = throttleInterval
        self.now = now
        self.sendPresenceUpdate = sendPresenceUpdate
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime]
        self.timestampFormatter = formatter
    }

    func report(scenePhase: ScenePhase, token: String?) async {
        await report(isForeground: Self.isForeground(scenePhase: scenePhase), token: token)
    }

    func report(isForeground: Bool, token: String?) async {
        currentIsForeground = isForeground
        await reportCurrentStateIfNeeded(token: token)
    }

    func reportCurrentStateIfNeeded(token: String?) async {
        let trimmedToken = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedToken.isEmpty else { return }

        let timestamp = now()
        if lastReportedToken == trimmedToken,
           lastReportedForeground == currentIsForeground,
           let lastReportedAt,
           timestamp.timeIntervalSince(lastReportedAt) < throttleInterval {
            return
        }

        await sendPresenceUpdate(
            trimmedToken,
            currentIsForeground,
            timestampFormatter.string(from: timestamp)
        )
        lastReportedToken = trimmedToken
        lastReportedForeground = currentIsForeground
        lastReportedAt = timestamp
    }

    private static func isForeground(scenePhase: ScenePhase) -> Bool {
        scenePhase == .active
    }
}
