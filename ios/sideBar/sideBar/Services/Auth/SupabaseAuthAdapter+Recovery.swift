import Foundation
import os

extension SupabaseAuthAdapter {
    /// Attempts to recover a session when the offline access window has expired.
    /// On success, applies the refreshed session. On failure, signs out.
    func attemptSessionRecovery() async {
        do {
            guard authClient.currentSession != nil else {
                diagnostics.record(AuthDiagnosticsEvent(
                    name: "session_recovery_failed",
                    metadata: [
                        "reason": "missing_current_session",
                        "auth_state": authState.rawValue
                    ]
                ))
                await transitionToSignedOut(clearPersistedState: true)
                return
            }
            let session = try await authClient.refreshSession()
            applySession(session)
            diagnostics.record(AuthDiagnosticsEvent(
                name: "session_recovery_succeeded",
                metadata: ["auth_state": authState.rawValue]
            ))
            logger.notice("Session recovery succeeded after offline window expiry")
        } catch {
            logger.warning("Session recovery failed: \(error.localizedDescription, privacy: .public)")
            let invalidAuth = isAuthInvalid(error)
            if invalidAuth {
                await transitionToSignedOut(clearPersistedState: true)
            } else {
                transitionToStale()
            }
            diagnostics.record(AuthDiagnosticsEvent(
                name: "session_recovery_failed",
                metadata: [
                    "classification": invalidAuth ? "invalid_auth" : "transient",
                    "auth_state": authState.rawValue
                ]
            ))
        }
    }
}
