import SwiftUI
import sideBarShared

private struct LargerTextQAMatrixView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                Text("Larger Text QA Matrix")
                    .appFont(.subheading)

                Group {
                    Text("Settings Pane")
                        .appFont(.caption)
                    GeneralSettingsView()
                }

                Group {
                    Text("Sidebar: Chats")
                        .appFont(.caption)
                    ConversationRow(
                        conversation: sampleConversation,
                        isSelected: false
                    )
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                }

                Group {
                    Text("Sidebar: Tasks")
                        .appFont(.caption)
                    TaskPanelRow(
                        title: "Review long-term roadmap and resolve pending platform migrations",
                        icon: AppIcon.Domain.tasks,
                        count: 12,
                        isSelected: false
                    )
                }

                Group {
                    Text("Sidebar: Websites")
                        .appFont(.caption)
                    WebsiteRow(
                        item: sampleWebsite,
                        isSelected: false
                    )
                }

                Group {
                    Text("Sidebar: Files")
                        .appFont(.caption)
                    FilesIngestionRow(
                        item: sampleIngestionItem,
                        isSelected: false
                    )
                }

                Group {
                    Text("Task Header")
                        .appFont(.caption)
                    ContentHeaderRow(
                        iconName: "checklist",
                        title: "Review long task header title for wrapping behavior at accessibility sizes",
                        subtitle: "12 open tasks",
                        titleStyle: .subheading,
                        titleLineLimit: 2,
                        subtitleLineLimit: 2,
                        titleSubtitleAxis: .vertical
                    )
                    .padding(DesignTokens.Spacing.md)
                    .background(DesignTokens.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
                }
            }
            .padding(DesignTokens.Spacing.md)
        }
        .background(DesignTokens.Colors.background)
    }

    private var sampleConversation: Conversation {
        Conversation(
            id: "preview-conversation",
            title: "Discuss migration plan for app-wide typography and accessibility refinements",
            titleGenerated: true,
            createdAt: "2026-02-23T00:00:00Z",
            updatedAt: "2026-02-23T00:00:00Z",
            messageCount: 37,
            firstMessage: nil,
            isArchived: false
        )
    }

    private var sampleWebsite: WebsiteItem {
        WebsiteItem(
            id: "preview-website",
            title: "How to design high-readability interfaces for very large text settings",
            url: "https://developer.apple.com/design/human-interface-guidelines/accessibility",
            domain: "developer.apple.com",
            savedAt: "2026-02-23T00:00:00Z",
            publishedAt: nil,
            pinned: false,
            pinnedOrder: nil,
            archived: false,
            faviconUrl: nil,
            faviconR2Key: nil,
            youtubeTranscripts: nil,
            readingTime: "7 min",
            updatedAt: "2026-02-23T00:00:00Z",
            lastOpenedAt: nil,
            deletedAt: nil
        )
    }

    private var sampleIngestionItem: IngestionListItem {
        IngestionListItem(
            file: IngestedFileMeta(
                id: "preview-file",
                filenameOriginal: "Accessibility roll-out checklist and release readiness notes.md",
                path: "/reports",
                mimeOriginal: "text/markdown",
                sizeBytes: 1024,
                sha256: nil,
                pinned: false,
                pinnedOrder: nil,
                category: "reports",
                sourceUrl: nil,
                sourceMetadata: nil,
                createdAt: "2026-02-23T00:00:00Z",
                updatedAt: nil,
                deletedAt: nil
            ),
            job: IngestionJob(
                status: "processing",
                stage: "transcribe",
                errorCode: nil,
                errorMessage: nil,
                userMessage: nil,
                progress: 0.42,
                attempts: 1,
                updatedAt: "2026-02-23T00:00:00Z"
            ),
            recommendedViewer: "text_original"
        )
    }
}

private struct PreviewAppTextSizeModifier: ViewModifier {
    let option: AppTextSizeOption

    func body(content: Content) -> some View {
        content
            .onAppear {
                UserDefaults.standard.set(option.rawValue, forKey: AppStorageKeys.appTextSize)
            }
    }
}

private extension View {
    func previewAppTextSize(_ option: AppTextSizeOption) -> some View {
        modifier(PreviewAppTextSizeModifier(option: option))
    }
}

struct LargerTextQAMatrix_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            LargerTextQAMatrixView()
                .previewAppTextSize(.system)
                .previewDisplayName("System • Default")
#if os(iOS)
            LargerTextQAMatrixView()
                .dynamicTypeSize(.accessibility5)
                .previewAppTextSize(.system)
                .previewDisplayName("System • AXXXL")
            LargerTextQAMatrixView()
                .dynamicTypeSize(.accessibility5)
                .previewAppTextSize(.large)
                .previewDisplayName("App Large • AXXXL")
#endif
        }
    }
}
