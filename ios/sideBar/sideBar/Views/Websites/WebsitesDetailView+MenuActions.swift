import SwiftUI

extension WebsitesDetailView {
    var websiteActionsMenu: some View {
        #if os(macOS)
        HeaderActionMenuControl(
            systemName: "ellipsis",
            accessibilityLabel: "Website options",
            chromeStyle: Self.actionControlChromeStyle
        ) {
            Button {
                togglePinnedForActiveWebsite()
            } label: {
                Label(pinActionTitle, systemImage: pinIconName)
            }
            Button {
                renameValue = viewModel.active?.title ?? ""
                isRenameDialogPresented = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                copyWebsiteContent()
            } label: {
                Label("Copy Markdown", systemImage: "doc.on.doc")
            }
            Button {
                copyWebsiteTitle()
            } label: {
                Label("Copy Title", systemImage: "textformat")
            }
            Button {
                copyWebsiteURL()
            } label: {
                Label("Copy URL", systemImage: "link")
            }
            Button {
                shareWebsiteURL()
            } label: {
                Label("Share URL", systemImage: "square.and.arrow.up.on.square")
            }
            Button {
                shareWebsiteText()
            } label: {
                Label("Share Text", systemImage: "square.and.arrow.up.on.square")
            }
            Button {
                exportWebsite()
            } label: {
                Label("Download", systemImage: "square.and.arrow.down")
            }
            Button {
                archiveActiveWebsite()
            } label: {
                Label(archiveMenuTitle, systemImage: archiveIconName)
            }
            Button(role: .destructive) {
                isDeleteAlertPresented = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .disabled(viewModel.active == nil)
        #else
        HeaderActionMenuButton(
            systemImage: "ellipsis",
            accessibilityLabel: "Website options",
            items: websiteHeaderMenuItems,
            isCompact: isCompact,
            chromeStyle: Self.actionControlChromeStyle
        )
        .disabled(viewModel.active == nil)
        #endif
    }

    #if os(iOS)
    var websiteToolbarMenu: some View {
        HeaderActionMenuButton(
            systemImage: "ellipsis",
            accessibilityLabel: "Website options",
            items: websiteHeaderMenuItems,
            isCompact: isCompact,
            chromeStyle: Self.actionControlChromeStyle
        )
        .disabled(viewModel.active == nil)
    }
    #endif

    private var websiteHeaderMenuItems: [SidebarMenuItem] {
        [
            .pin(isPinned: isPinned) {
                togglePinnedForActiveWebsite()
            },
            .rename {
                renameValue = viewModel.active?.title ?? ""
                isRenameDialogPresented = true
            },
            .copyMarkdown {
                copyWebsiteContent()
            },
            SidebarMenuItem(title: "Copy Title", systemImage: "textformat", role: nil) {
                copyWebsiteTitle()
            },
            SidebarMenuItem(title: "Copy URL", systemImage: "link", role: nil) {
                copyWebsiteURL()
            },
            .share {
                shareWebsiteURL()
            },
            .shareText {
                shareWebsiteText()
            },
            .download {
                exportWebsite()
            },
            .archive(isArchived: isArchived) {
                archiveActiveWebsite()
            },
            .delete {
                isDeleteAlertPresented = true
            }
        ]
    }
}

struct WebsiteContentQuickActionsPill: View {
    static let controlTouchTarget: CGFloat = HeaderActionControlMetrics.chromeHeight
    static let controlIconSize: CGFloat = HeaderActionControlMetrics.iconFrameHeight

    let isPinned: Bool
    let isArchived: Bool
    let onPinToggle: () -> Void
    let onArchiveToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            iconButton(
                systemName: isPinned ? "pin.slash" : "pin",
                accessibilityLabel: isPinned ? "Unpin website" : "Pin website",
                role: nil,
                action: onPinToggle
            )
            divider
            iconButton(
                systemName: isArchived ? "archivebox.fill" : "archivebox",
                accessibilityLabel: isArchived ? "Unarchive website" : "Archive website",
                role: nil,
                action: onArchiveToggle
            )
            divider
            iconButton(
                systemName: "trash",
                accessibilityLabel: "Delete website",
                role: .destructive,
                action: onDelete
            )
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xsPlus)
        .glassEffect(.regular.interactive(), in: Capsule())
    }

    @ViewBuilder
    private func iconButton(
        systemName: String,
        accessibilityLabel: String,
        role: ButtonRole?,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemName)
                .appFont(.labelMd)
                .frame(width: Self.controlIconSize, height: Self.controlIconSize)
                .frame(width: Self.controlTouchTarget, height: Self.controlTouchTarget)
                .foregroundStyle(
                    role == .destructive ? DesignTokens.Colors.error : DesignTokens.Colors.textPrimary
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var divider: some View {
        Rectangle()
            .fill(DesignTokens.Colors.border)
            .frame(width: 1, height: 14)
    }
}
