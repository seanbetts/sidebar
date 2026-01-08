import Foundation
import SwiftUI

@MainActor
public final class NavigationState: ObservableObject {
    @AppStorage(AppStorageKeys.lastSelectedSection) public var lastSectionRaw: String = AppSection.chat.rawValue
    @AppStorage(AppStorageKeys.sidebarWidth) public var sidebarWidth: Double = 280

    public var lastSection: AppSection {
        get { AppSection(rawValue: lastSectionRaw) ?? .chat }
        set { lastSectionRaw = newValue.rawValue }
    }
}
