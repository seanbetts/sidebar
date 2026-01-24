import Foundation

extension AppEnvironment {
    public func refreshAuthState() {
        let wasAuthenticated = isAuthenticated
        isAuthenticated = container.authSession.accessToken != nil
        if wasAuthenticated && !isAuthenticated {
            container.cacheClient.clear()
            chatStore.reset()
            notesStore.reset()
            websitesStore.reset()
            ingestionStore.reset()
            tasksStore.reset()
            notesViewModel.clearSelection()
            websitesViewModel.clearSelection()
            ingestionViewModel.clearSelection()
            sessionExpiryWarning = nil
        }
        if isAuthenticated {
            biometricMonitor.startMonitoring()
        } else {
            biometricMonitor.stopMonitoring()
        }
        realtimeClientStopStart()
    }

    public func beginSignOut() async {
        signOutEvent = UUID()
        sessionExpiryWarning = nil
        await container.authSession.signOut()
        refreshAuthState()
    }

    public func consumeExtensionEvents() async {
        let events = ExtensionEventStore.shared.consumeEvents()
        guard !events.isEmpty else { return }
        guard isAuthenticated else { return }
        let websiteEvents = events.filter { $0.type == .websiteSaved }
        guard !websiteEvents.isEmpty else { return }
        for event in websiteEvents {
            if let url = event.websiteUrl {
                websitesViewModel.showPendingFromExtension(url: url)
            }
        }
    }
}
