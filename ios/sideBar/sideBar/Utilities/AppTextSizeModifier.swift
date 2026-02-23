import SwiftUI

struct AppTextSizeModifier: ViewModifier {
    @AppStorage(AppStorageKeys.appTextSize) private var appTextSizeRaw = AppTextSizeOption.system.rawValue

    @ViewBuilder
    func body(content: Content) -> some View {
        let option = AppTextSizeOption.resolved(from: appTextSizeRaw)
        #if os(iOS)
        if let dynamicTypeSize = option.dynamicTypeSize {
            content.dynamicTypeSize(dynamicTypeSize)
        } else {
            content
        }
        #else
        content.font(AppFontStyle.body.font(for: option))
        #endif
    }
}

extension View {
    func appTextSize() -> some View {
        modifier(AppTextSizeModifier())
    }
}
