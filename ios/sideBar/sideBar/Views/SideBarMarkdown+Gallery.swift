import SwiftUI

struct MarkdownGalleryView: View {
    let gallery: MarkdownRendering.MarkdownGallery

    private let gridSpacing: CGFloat = SideBarMarkdownLayout.gallerySpacing
    private let minImageWidth: CGFloat = SideBarMarkdownLayout.galleryMinImageWidth
    @State private var availableWidth: CGFloat = 0

    var body: some View {
        let rows = chunked(gallery.imageUrls, size: columns(for: availableWidth))
        let imageWidth = imageWidth(for: availableWidth)
        VStack(alignment: .center, spacing: gridSpacing) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: gridSpacing) {
                    ForEach(rows[rowIndex], id: \.self) { urlString in
                        MarkdownGalleryImageView(
                            urlString: urlString,
                            maxSize: CGSize(
                                width: imageWidth,
                                height: SideBarMarkdownLayout.maxImageSize.height
                            )
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            if let caption = gallery.caption, !caption.isEmpty {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        availableWidth = proxy.size.width
                    }
                    .onChange(of: proxy.size.width) { _, newValue in
                        availableWidth = newValue
                    }
            }
        )
    }

    private func columns(for availableWidth: CGFloat) -> Int {
        let effectiveWidth = max(availableWidth, minImageWidth)
        let count = Int((effectiveWidth + gridSpacing) / (minImageWidth + gridSpacing))
        return max(1, count)
    }

    private func imageWidth(for availableWidth: CGFloat) -> CGFloat {
        let effectiveWidth = max(availableWidth, minImageWidth)
        let columnCount = columns(for: availableWidth)
        let totalSpacing = gridSpacing * CGFloat(max(columnCount - 1, 0))
        let columnWidth = (effectiveWidth - totalSpacing) / CGFloat(columnCount)
        return min(columnWidth, SideBarMarkdownLayout.maxImageSize.width)
    }

    private func chunked(_ items: [String], size: Int) -> [[String]] {
        guard size > 0 else { return [items] }
        var chunks: [[String]] = []
        var index = 0
        while index < items.count {
            let end = min(index + size, items.count)
            chunks.append(Array(items[index..<end]))
            index = end
        }
        return chunks
    }
}

private struct MarkdownGalleryImageView: View {
    let urlString: String
    let maxSize: CGSize

    var body: some View {
        if let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: maxSize.width, maxHeight: maxSize.height)
                case .failure:
                    Image(systemName: "photo")
                        .font(DesignTokens.Typography.display)
                        .foregroundStyle(.secondary)
                case .empty:
                    ProgressView()
                @unknown default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
