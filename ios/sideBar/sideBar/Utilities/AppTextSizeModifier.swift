import SwiftUI

struct AppTextSizeModifier: ViewModifier {
    @AppStorage(AppStorageKeys.appTextSize) private var appTextSizeRaw = AppTextSizeOption.system.rawValue

    func body(content: Content) -> some View {
        let option = AppTextSizeOption.resolved(from: appTextSizeRaw)
        content.font(AppFontStyle.body.font(for: option))
    }
}

struct AppControlSizeModifier: ViewModifier {
    @AppStorage(AppStorageKeys.appTextSize) private var appTextSizeRaw = AppTextSizeOption.system.rawValue

    func body(content: Content) -> some View {
        let option = AppTextSizeOption.resolved(from: appTextSizeRaw)
        content.controlSize(option.controlSize)
    }
}

extension View {
    func appTextSize() -> some View {
        modifier(AppTextSizeModifier())
    }

    func appControlSize() -> some View {
        modifier(AppControlSizeModifier())
    }
}
