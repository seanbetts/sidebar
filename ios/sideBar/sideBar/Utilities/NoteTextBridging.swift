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
    }

    var attributedNoteTextSurface: AttributedNoteTextSurfaceAttributes.Type {
        AttributedNoteTextSurfaceAttributes.self
    }
}
