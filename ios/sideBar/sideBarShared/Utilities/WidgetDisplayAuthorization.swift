import Foundation

/// Decides whether widgets may render protected cached content.
public enum WidgetDisplayAuthorization {
    /// Auth and cache state used to decide whether protected widget content can render.
    public enum DisplayState: Equatable, Sendable {
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
