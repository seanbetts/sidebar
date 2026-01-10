#if canImport(MarkdownUI)
import MarkdownUI
#endif
import SwiftUI

struct SideBarMarkdown: View {
    let text: String
    let preprocessor: (String) -> String

    init(text: String, preprocessor: @escaping (String) -> String = MarkdownRendering.normalizeTaskLists) {
        self.text = text
        self.preprocessor = preprocessor
    }

    var body: some View {
        #if canImport(MarkdownUI)
        Markdown(preprocessor(text))
            .markdownTextStyle(\.strikethrough) {
                StrikethroughStyle(.single)
                ForegroundColor(.secondary)
            }
        #else
        Text(text)
        #endif
    }
}
