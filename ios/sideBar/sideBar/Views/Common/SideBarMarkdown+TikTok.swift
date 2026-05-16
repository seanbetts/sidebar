import SwiftUI
import sideBarShared

struct SideBarTikTokEmbedBlock: View {
    let embed: MarkdownRendering.MarkdownTikTokEmbed
    @State private var isPlayerLoaded = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            ZStack {
                TikTokEmbedView(embed: embed) { isLoaded in
                    isPlayerLoaded = isLoaded
                }
                .opacity(isPlayerLoaded ? 1 : 0.001)

                if !isPlayerLoaded {
                    TikTokFallbackCard(embed: embed) {
                        guard let url = URL(string: embed.sourceURL) else { return }
                        openURL(url)
                    }
                }
            }
            .aspectRatio(9 / 16, contentMode: .fit)
            .frame(maxWidth: 420)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct TikTokFallbackCard: View {
    let embed: MarkdownRendering.MarkdownTikTokEmbed
    let openAction: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            if let url = URL(string: embed.thumbnailURL) {
                CachedMarkdownRemoteImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Rectangle()
                            .fill(DesignTokens.Colors.muted)
                    case .empty:
                        Rectangle()
                            .fill(DesignTokens.Colors.muted)
                            .overlay(LoadingIndicatorView(size: LoadingIndicatorSize.panel))
                    }
                }
            } else {
                Rectangle()
                    .fill(DesignTokens.Colors.muted)
            }

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.75)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(appIcon: AppIcon.Media.playFilled)
                        .appFont(.titleLg)
                        .foregroundStyle(.white)
                    Text("Loading TikTok…")
                        .appFont(.footnote)
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 6) {
                    if let authorName = embed.authorName, !authorName.isEmpty {
                        Text(authorName)
                            .appFont(.caption)
                            .foregroundStyle(.white.opacity(0.92))
                    }
                    Text(embed.title)
                        .appFont(.footnote)
                        .foregroundStyle(.white)
                        .lineLimit(4)
                }

                Button(action: openAction) {
                    Text("Open on TikTok")
                        .appFont(.footnote)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.92))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DesignTokens.Colors.muted)
    }
}
