#if canImport(MarkdownUI)
import MarkdownUI
import sideBarShared
import SwiftUI

struct CappedImageProvider: ImageProvider {
    let maxSize: CGSize

    func makeImage(url: URL?) -> some View {
        CachedMarkdownRemoteImage(url: url) { phase in
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
                        .appFont(.size32Regular)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            case .empty:
                HStack {
                    Spacer(minLength: 0)
                    LoadingIndicatorView(size: LoadingIndicatorSize.control)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
#endif
