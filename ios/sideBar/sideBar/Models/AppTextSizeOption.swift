import Foundation
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

    var scaleMultiplier: CGFloat {
        switch self {
        case .system:
            return 1
        case .small:
            return 0.9
        case .medium:
            return 1.05
        case .large:
            return 1.2
        }
    }

    static func resolved(from rawValue: String) -> AppTextSizeOption {
        AppTextSizeOption(rawValue: rawValue) ?? .system
    }

    static var currentScaleMultiplier: CGFloat {
        let rawValue = UserDefaults.standard.string(forKey: AppStorageKeys.appTextSize) ?? AppTextSizeOption.system.rawValue
        return resolved(from: rawValue).scaleMultiplier
    }
}
