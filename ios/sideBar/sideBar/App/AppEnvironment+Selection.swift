import Foundation

extension AppEnvironment {
    func refreshConnectivityStatusFromBannerTap() async -> Bool {
        let wasUnavailable = !connectivityMonitor.offlineCapabilityPolicy.canAttemptServerRead
        await connectivityMonitor.refreshStatusNow()
        let isStillUnavailable = !connectivityMonitor.offlineCapabilityPolicy.canAttemptServerRead
        if wasUnavailable && !isStillUnavailable {
            await syncCoordinator.refreshAll()
        }
        return isStillUnavailable
    }

    func realtimeClientStopStart() {
        guard authState == .active,
              let userId = container.authSession.userId,
              let token = container.authSession.authorizationToken
        else {
            realtimeClient.stop()
            return
        }
        Task {
            await realtimeClient.start(userId: userId, accessToken: token)
        }
    }

    func observeSelectionChanges() {
        // Phase 7: cross-domain selection is now pane-scoped by workspace visibility.
        // Keep observers disabled to avoid destructive global selection clearing.
    }
}
