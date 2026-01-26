import Combine
import Foundation

extension AppEnvironment {
    func configureSubscriptions() {
        if let authAdapter = container.authSession as? SupabaseAuthAdapter {
            bindAuthAdapter(authAdapter)
        }
        forwardObjectWillChange()
        monitorNetwork()

        // Sync initial auth state to widgets
        WidgetDataManager.shared.updateAuthState(isAuthenticated: isAuthenticated)
    }

    func configureRealtimeClient() {
        if let realtimeClient = realtimeClient as? SupabaseRealtimeAdapter {
            realtimeClient.handler = self
        }
        realtimeClientStopStart()
    }

    private func bindAuthAdapter(_ authAdapter: SupabaseAuthAdapter) {
        authAdapter.$accessToken
            .sink { [weak self] _ in
                self?.refreshAuthState()
            }
            .store(in: &cancellables)

        authAdapter.$authError
            .compactMap { $0 }
            .sink { [weak self, weak authAdapter] event in
                self?.toastCenter.show(message: event.message)
                authAdapter?.clearAuthError()
            }
            .store(in: &cancellables)

        authAdapter.$sessionExpiryWarning
            .sink { [weak self] warning in
                DispatchQueue.main.async {
                    self?.sessionExpiryWarning = warning
                }
            }
            .store(in: &cancellables)
    }

    private func forwardObjectWillChange() {
        settingsViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        chatViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        notesViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        notesEditorViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        websitesViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        ingestionViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        weatherViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    private func monitorNetwork() {
        networkMonitor.$isOffline
            .removeDuplicates()
            .sink { [weak self] isOffline in
                self?.isOffline = isOffline
                if isOffline == false {
                    self?.refreshOnReconnect()
                }
            }
            .store(in: &cancellables)
    }
}
