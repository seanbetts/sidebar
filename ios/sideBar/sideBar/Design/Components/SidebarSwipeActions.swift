import SwiftUI

extension View {
    @ViewBuilder
    func sidebarListSwipeActions(
        leadingTitle: String? = nil,
        leadingSystemImage: String? = nil,
        onLeading: (() -> Void)? = nil,
        trailingDeleteTitle: String = "Delete",
        trailingDeleteSystemImage: String = "trash",
        onDelete: (() -> Void)? = nil
    ) -> some View {
        #if os(iOS)
        self
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                if let leadingTitle, let onLeading {
                    Button {
                        onLeading()
                    } label: {
                        if let leadingSystemImage {
                            Label(leadingTitle, systemImage: leadingSystemImage)
                        } else {
                            Text(leadingTitle)
                        }
                    }
                    .tint(DesignTokens.Colors.actionPrimary)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                if let onDelete {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label(trailingDeleteTitle, systemImage: trailingDeleteSystemImage)
                    }
                    .tint(DesignTokens.Colors.actionDestructive)
                }
            }
        #else
        self
        #endif
    }
}
