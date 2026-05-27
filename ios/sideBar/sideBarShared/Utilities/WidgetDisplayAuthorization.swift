import Foundation

/// Decides whether widgets may render protected cached content.
public enum WidgetDisplayAuthorization {
    /// Shared app-group key for the persisted widget display state.
    public static let displayStateStorageKey = "widgetDisplayState"

    /// Auth and cache state used to decide whether protected widget content can render.
    public enum DisplayState: String, Equatable, Sendable, Codable {
        /// A valid authenticated session is available.
        case authenticated
        /// Auth state cannot currently be proven, but a previously rendered snapshot exists.
        case transientlyUnavailable
        /// The user is signed out and no cached display exception applies.
        case signedOut
        /// The session exists but requires explicit reauthentication before protected display.
        case reauthenticationRequired
    }

    /// Returns the display state represented by current auth and cache inputs.
    public static func displayState(isAuthenticated: Bool, hasCachedSnapshot: Bool) -> DisplayState {
        if isAuthenticated {
            return .authenticated
        }
        if hasCachedSnapshot {
            return .transientlyUnavailable
        }
        return .signedOut
    }

    /// Returns the display state represented by a persisted state plus legacy auth/cache inputs.
    public static func displayState(
        storedState: DisplayState?,
        isAuthenticated: Bool,
        hasCachedSnapshot: Bool
    ) -> DisplayState {
        guard let storedState else {
            return displayState(
                isAuthenticated: isAuthenticated,
                hasCachedSnapshot: hasCachedSnapshot
            )
        }

        switch storedState {
        case .authenticated:
            return .authenticated
        case .transientlyUnavailable:
            return hasCachedSnapshot ? .transientlyUnavailable : .signedOut
        case .signedOut, .reauthenticationRequired:
            return storedState
        }
    }

    /// Returns whether a widget may display content for the current display state.
    public static func canDisplayContent(for state: DisplayState) -> Bool {
        switch state {
        case .authenticated, .transientlyUnavailable:
            return true
        case .reauthenticationRequired, .signedOut:
            return false
        }
    }
}
