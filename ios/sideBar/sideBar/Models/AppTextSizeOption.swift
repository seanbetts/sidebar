import SwiftUI

public enum AppTextSizeOption: String, CaseIterable, Identifiable {
    case system
    case small
    case medium
    case large

    public var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            return "System"
        case .small:
            return "Small"
        case .medium:
            return "Medium"
        case .large:
            return "Large"
        }
    }

    var dynamicTypeSize: DynamicTypeSize? {
        switch self {
        case .system:
            return nil
        case .small:
            return .medium
        case .medium:
            return .large
        case .large:
            return .xLarge
        }
    }

    static func resolved(from rawValue: String) -> AppTextSizeOption {
        AppTextSizeOption(rawValue: rawValue) ?? .system
    }
}
