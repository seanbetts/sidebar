import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@available(iOS 26.0, macOS 26.0, *)
extension AttributeScopes {
    struct AttributedNoteTextSurfaceAttributes: AttributeScope {
        let noteTextEditor: NoteTextEditorAttributes
        #if os(iOS)
        let uiKit: UIKitAttributes
        #elseif os(macOS)
        let appKit: AppKitAttributes
        #endif
    }

    var attributedNoteTextSurface: AttributedNoteTextSurfaceAttributes.Type {
        AttributedNoteTextSurfaceAttributes.self
    }
}
