import SwiftUI

extension View {
    @ViewBuilder
    func navigationBarTitleDisplayModeInline() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func textInputAutocapitalizationSentences() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.sentences)
        #else
        self
        #endif
    }

    @ViewBuilder
    func submitLabelDone() -> some View {
        #if os(iOS)
        self.submitLabel(.done)
        #else
        self
        #endif
    }
}
