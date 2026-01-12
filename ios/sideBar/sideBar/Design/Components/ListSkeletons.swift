import SwiftUI

struct SidebarListSkeleton: View {
    let rowCount: Int
    let showSubtitle: Bool

    init(rowCount: Int = 6, showSubtitle: Bool = false) {
        self.rowCount = rowCount
        self.showSubtitle = showSubtitle
    }

    var body: some View {
        List {
            Section {
                ForEach(0..<rowCount, id: \.self) { index in
                    SidebarSkeletonRow(showSubtitle: showSubtitle, variation: index)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(DesignTokens.Colors.sidebar)
    }
}

private struct SidebarSkeletonRow: View {
    let showSubtitle: Bool
    let variation: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SkeletonLine(width: titleWidth)
            if showSubtitle {
                SkeletonLine(width: subtitleWidth, height: 10)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
        .listRowInsets(
            EdgeInsets(
                top: 0,
                leading: DesignTokens.Spacing.sm,
                bottom: 0,
                trailing: DesignTokens.Spacing.sm
            )
        )
        .listRowBackground(rowBackground)
    }

    private var titleWidth: CGFloat {
        let widths: [CGFloat] = [0.62, 0.78, 0.54, 0.7, 0.84, 0.58]
        return widths[variation % widths.count]
    }

    private var subtitleWidth: CGFloat {
        let widths: [CGFloat] = [0.4, 0.52, 0.36, 0.46, 0.6, 0.42]
        return widths[variation % widths.count]
    }

    private var rowBackground: Color {
        #if os(macOS)
        return DesignTokens.Colors.sidebar
        #else
        return DesignTokens.Colors.background
        #endif
    }
}

private struct SkeletonLine: View {
    let width: CGFloat
    let height: CGFloat

    init(width: CGFloat, height: CGFloat = 14) {
        self.width = width
        self.height = height
    }

    var body: some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xs, style: .continuous)
                .fill(DesignTokens.Colors.textTertiary.opacity(0.35))
                .frame(width: proxy.size.width * width, height: height)
        }
        .frame(height: height)
    }
}
