import SwiftUI
#if os(iOS)
import UIKit
#endif

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

    @ViewBuilder
    func phoneSheetGrabBarVisible() -> some View {
        #if os(iOS)
        self.presentationDragIndicator(
            UIDevice.current.userInterfaceIdiom == .phone ? .visible : .automatic
        )
        #else
        self
        #endif
    }

    @ViewBuilder
    func settingsSheetGrabBarVisible() -> some View {
        #if os(iOS)
        self.presentationDragIndicator(.visible)
        #else
        self
        #endif
    }
}
