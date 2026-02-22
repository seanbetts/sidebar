import Foundation

@MainActor
@available(iOS 26.0, macOS 26.0, *)
enum AttributedNoteFormattingCommands {
    static func apply(_ formatting: MarkdownFormatting, on viewModel: NativeMarkdownEditorViewModel) {
        if applyInline(formatting, on: viewModel) {
            return
        }
        if applyBlock(formatting, on: viewModel) {
            return
        }
        applySpecial(formatting, on: viewModel)
    }

    private static func applyInline(
        _ formatting: MarkdownFormatting,
        on viewModel: NativeMarkdownEditorViewModel
    ) -> Bool {
        switch formatting {
        case .bold:
            viewModel.toggleInlineIntent(.stronglyEmphasized)
            return true
        case .italic:
            viewModel.toggleInlineIntent(.emphasized)
            return true
        case .inlineCode:
            viewModel.toggleInlineIntent(.code)
            return true
        case .strikethrough:
            viewModel.toggleStrikethrough()
            return true
        default:
            return false
        }
    }

    private static func applyBlock(
        _ formatting: MarkdownFormatting,
        on viewModel: NativeMarkdownEditorViewModel
    ) -> Bool {
        switch formatting {
        case .heading(let level):
            viewModel.setBlockKind(viewModel.headingKind(for: level))
            return true
        case .bulletList:
            viewModel.setBlockKind(.bulletList, listDepth: 1)
            return true
        case .orderedList:
            viewModel.setBlockKind(.orderedList, listDepth: 1)
            return true
        case .taskList:
            viewModel.setBlockKind(.taskUnchecked, listDepth: 1)
            return true
        case .blockquote:
            viewModel.setBlockKind(.blockquote)
            return true
        case .codeBlock:
            viewModel.setBlockKind(.codeBlock)
            return true
        default:
            return false
        }
    }

    private static func applySpecial(
        _ formatting: MarkdownFormatting,
        on viewModel: NativeMarkdownEditorViewModel
    ) {
        switch formatting {
        case .link(let url):
            viewModel.insertLink(url)
        case .horizontalRule:
            viewModel.insertHorizontalRule()
        default:
            return
        }
    }
}
