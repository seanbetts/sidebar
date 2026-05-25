import Foundation
#if os(iOS)
import UserNotifications
#elseif os(macOS)
import AppKit
#endif

@MainActor public protocol TaskBadgeUpdating {
    func update(count: Int)
}

public struct LiveTaskBadgeUpdater: TaskBadgeUpdating {
    public init() {}

    public func update(count: Int) {
        #if os(iOS)
        UNUserNotificationCenter.current().setBadgeCount(count, withCompletionHandler: nil)
        #elseif os(macOS)
        NSApplication.shared.dockTile.badgeLabel = Self.badgeLabel(for: count)
        #endif
    }

    #if os(macOS)
    nonisolated static func badgeLabel(for count: Int) -> String? {
        count > 0 ? String(count) : nil
    }
    #endif
}
