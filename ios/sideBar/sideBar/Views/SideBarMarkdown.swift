#if canImport(MarkdownUI)
import MarkdownUI
#endif
import SwiftUI

struct SideBarMarkdown: View {
    let text: String

    var body: some View {
        #if canImport(MarkdownUI)
        Markdown(MarkdownRendering.normalizeTaskLists(text))
            .markdownTextStyle(\.strikethrough) {
                StrikethroughStyle(.single)
                ForegroundColor(.secondary)
            }
        #else
        Text(text)
        #endif
    }
}
