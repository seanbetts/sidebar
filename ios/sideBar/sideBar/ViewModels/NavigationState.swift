import Foundation
import SwiftUI
import Combine

// NOTE: Revisit to prefer native-first data sources where applicable.

/// Persists navigation selections and layout preferences.
public nonisolated final class NavigationState: ObservableObject {
    public let objectWillChange = ObservableObjectPublisher()

    @MainActor @AppStorage(AppStorageKeys.lastSelectedSection) public var lastSectionRaw: String = AppSection.chat.rawValue
    @MainActor @AppStorage(AppStorageKeys.sidebarWidth) public var sidebarWidth: Double = 280

    @MainActor
    public var lastSection: AppSection {
        get { AppSection(rawValue: lastSectionRaw) ?? .chat }
        set { lastSectionRaw = newValue.rawValue }
    }

    // NOTE: Extend to support per-platform navigation state (tabs vs split).
}
