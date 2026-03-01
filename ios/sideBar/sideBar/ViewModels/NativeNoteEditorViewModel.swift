import Foundation

@available(iOS 26.0, macOS 26.0, *)
/// Prevent new references to the legacy markdown-named editor type.
@available(*, unavailable, renamed: "NativeNoteEditorViewModel")
public typealias NativeMarkdownEditorViewModel = NativeNoteEditorViewModel
