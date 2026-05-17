import SwiftUI
import sideBarShared

extension View {
    @ViewBuilder
    func sidebarListSwipeActions(
        leadingTitle: String? = nil,
        leadingIcon: AppIcon? = nil,
        onLeading: (() -> Void)? = nil,
        trailingDeleteTitle: String = "Delete",
        trailingDeleteIcon: AppIcon = AppIcon.Action.delete,
        onDelete: (() -> Void)? = nil
    ) -> some View {
        #if os(iOS)
        self
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                if let leadingTitle, let onLeading {
                    Button {
                        onLeading()
                    } label: {
                        if let leadingIcon {
                            Label(leadingTitle, systemImage: leadingIcon.rawValue)
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
                        Haptics.notification(.error)
                        onDelete()
                    } label: {
                        Label(trailingDeleteTitle, systemImage: trailingDeleteIcon.rawValue)
                    }
                    .tint(DesignTokens.Colors.actionDestructive)
                }
            }
        #else
        self
        #endif
    }
}
