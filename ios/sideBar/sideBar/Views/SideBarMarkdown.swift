#if canImport(MarkdownUI)
import MarkdownUI
#endif
import SwiftUI

struct SideBarMarkdown: View {
    let text: String
    let preprocessor: (String) -> String
    private let maxImageSize = CGSize(width: 450, height: 450)

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
            .markdownTextStyle(\.link) {
                UnderlineStyle(.single)
            }
            .markdownImageProvider(CappedImageProvider(maxSize: maxImageSize))
        #else
        Text(text)
        #endif
    }
}

#if canImport(MarkdownUI)
private struct CappedImageProvider: ImageProvider {
    let maxSize: CGSize

    func makeImage(url: URL?) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                HStack {
                    Spacer(minLength: 0)
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: maxSize.width, maxHeight: maxSize.height)
                    Spacer(minLength: 0)
                }
            case .failure:
                HStack {
                    Spacer(minLength: 0)
                    Image(systemName: "photo")
                        .font(.system(size: 32, weight: .regular))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            case .empty:
                HStack {
                    Spacer(minLength: 0)
                    ProgressView()
                    Spacer(minLength: 0)
                }
            @unknown default:
                EmptyView()
            }
        }
    }
}
#endif
