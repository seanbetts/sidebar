import Foundation
import SwiftUI
import Combine

// TODO: Revisit to prefer native-first data sources where applicable.

@MainActor
/// Persists navigation selections and layout preferences.
public final class NavigationState: ObservableObject {
    public let objectWillChange = ObservableObjectPublisher()

    @AppStorage(AppStorageKeys.lastSelectedSection) public var lastSectionRaw: String = AppSection.chat.rawValue
    @AppStorage(AppStorageKeys.sidebarWidth) public var sidebarWidth: Double = 280

    public var lastSection: AppSection {
        get { AppSection(rawValue: lastSectionRaw) ?? .chat }
        set { lastSectionRaw = newValue.rawValue }
    }

    // TODO: Extend to support per-platform navigation state (tabs vs split).
}
