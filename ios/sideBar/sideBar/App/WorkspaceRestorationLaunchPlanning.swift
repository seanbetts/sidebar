import Foundation
import sideBarShared

struct RestorationSaveSuppressionPolicy: Equatable {
    static let launchApplicationQueuedSaveSuppressions = 4

    var isApplying: Bool
    var queuedSaveSuppressions: Int

    mutating func beginLaunchApplication() {
        isApplying = true
        queuedSaveSuppressions = Self.launchApplicationQueuedSaveSuppressions
    }

    mutating func finishLaunchApplication() {
        isApplying = false
    }

    mutating func shouldSuppressSave() -> Bool {
        if isApplying {
            return true
        }
        if queuedSaveSuppressions > 0 {
            queuedSaveSuppressions -= 1
            return true
        }
        return false
    }

    mutating func clearQueuedSuppressions() {
        queuedSaveSuppressions = 0
    }
}

struct InitialSelectionReadinessPlan: Equatable {
    let shouldProceed: Bool
    let didSetInitialSelection: Bool

    static func resolve(
        authState: AuthState,
        isProtectedContentReady: Bool,
        didSetInitialSelection: Bool
    ) -> Self {
        guard authState == .active, isProtectedContentReady, !didSetInitialSelection else {
            return Self(
                shouldProceed: false,
                didSetInitialSelection: didSetInitialSelection
            )
        }
        return Self(shouldProceed: true, didSetInitialSelection: true)
    }
}

extension WorkspaceRestorationPlanner {
    static func freshTodayTaskCountForLaunch(
        previousCounts: TaskCountsResponse?,
        currentCounts: TaskCountsResponse?,
        errorMessage: String?
    ) -> Int {
        guard errorMessage == nil, let currentCounts else { return 0 }
        if let previousCounts, previousCounts.generatedAt == currentCounts.generatedAt {
            return 0
        }
        return currentCounts.counts.today
    }
}
