import XCTest
@testable import sideBar

final class OfflineAvailabilityPresentationTests: XCTestCase {
    func testSharedOfflineUnavailablePlaceholderCopyIsConsistentAcrossSurfaces() {
        XCTAssertEqual(
            DetailOfflineUnavailableResource.note.title,
            "This note isn't available offline yet"
        )
        XCTAssertEqual(
            DetailOfflineUnavailableResource.website.title,
            "This website isn't available offline yet"
        )
        XCTAssertEqual(
            DetailOfflineUnavailableResource.file.title,
            "This file isn't available offline yet"
        )
        XCTAssertEqual(
            DetailOfflineUnavailableResource.chat.title,
            "This chat isn't available offline yet"
        )
        XCTAssertEqual(
            DetailOfflineUnavailableResource.taskList.title,
            "This task list isn't available offline yet"
        )
        XCTAssertEqual(
            DetailOfflineUnavailableResource.chat.subtitle,
            "Open it while online on this device to keep it available here."
        )
        XCTAssertEqual(
            DetailOfflineUnavailableResource.note.iconName,
            AppSection.notes.iconName
        )
        XCTAssertEqual(
            DetailOfflineUnavailableResource.website.iconName,
            AppSection.websites.iconName
        )
        XCTAssertEqual(
            DetailOfflineUnavailableResource.file.iconName,
            AppSection.files.iconName
        )
        XCTAssertEqual(
            DetailOfflineUnavailableResource.chat.iconName,
            AppSection.chat.iconName
        )
        XCTAssertEqual(
            DetailOfflineUnavailableResource.taskList.iconName,
            AppSection.tasks.iconName
        )
    }

    func testNotesDetailViewUsesSharedOfflineUnavailablePlaceholder() throws {
        let normalized = try source(named: "Views/Notes/NotesDetailView.swift")
            .normalizedForSourceAssertions()

        XCTAssertTrue(normalized.contains("DetailOfflineUnavailablePlaceholder(resource:.note)"))
    }

    func testWebsitesDetailViewUsesSharedOfflineUnavailablePlaceholderAndBlocksWelcomeStateForSelection() throws {
        let normalized = try source(named: "Views/Websites/WebsitesDetailView.swift")
            .normalizedForSourceAssertions()

        XCTAssertTrue(normalized.contains("DetailOfflineUnavailablePlaceholder(resource:.website)"))
        XCTAssertTrue(normalized.contains("&&viewModel.selectedWebsiteId==nil"))
    }

    func testWebsitesDetailViewShowsOfflineUnavailableBeforeLoadingForUncachedSelection() throws {
        let normalized = try source(named: "Views/Websites/WebsitesDetailView.swift")
            .normalizedForSourceAssertions()

        XCTAssertTrue(
            normalized.contains(
                "}elseifviewModel.selectedWebsiteId!=nil,!canAttemptServerRead,"
                    + "!viewModel.hasCachedSelectedWebsiteDetail{"
                    + "DetailOfflineUnavailablePlaceholder(resource:.website)"
            )
        )
    }

    func testWebsitesPanelTracksSelectionFromSelectedWebsiteIdInsteadOfLoadedDetail() throws {
        let normalized = try source(named: "Views/SidebarPanels/WebsitesPanel.swift")
            .normalizedForSourceAssertions()

        XCTAssertTrue(normalized.contains(".onChange(of:viewModel.selectedWebsiteId)"))
        XCTAssertFalse(normalized.contains(".onChange(of:viewModel.active?.id)"))
    }

    func testFilesDetailViewsUseSharedOfflineUnavailablePlaceholder() throws {
        let filesNormalized = try source(named: "Views/Files/FilesViewComponents.swift")
            .normalizedForSourceAssertions()
        let detailNormalized = try source(named: "Views/Files/IngestionDetailView.swift")
            .normalizedForSourceAssertions()

        XCTAssertTrue(filesNormalized.contains("DetailOfflineUnavailablePlaceholder(resource:.file)"))
        XCTAssertTrue(detailNormalized.contains("DetailOfflineUnavailablePlaceholder(resource:.file)"))
    }

    func testFilesDetailViewShowsOfflineUnavailableBeforeLoadingForUncachedSelection() throws {
        let normalized = try source(named: "Views/Files/IngestionDetailView.swift")
            .normalizedForSourceAssertions()

        XCTAssertTrue(
            normalized.contains(
                "}elseif!canAttemptServerRead&&viewModel.isSelectedPreviewUnavailableOffline{"
                    + "DetailOfflineUnavailablePlaceholder(resource:.file)"
            )
        )
    }

    func testTasksDetailViewUsesSharedOfflineUnavailablePlaceholder() throws {
        let normalized = try source(named: "Views/Tasks/TasksDetailView.swift")
            .normalizedForSourceAssertions()

        XCTAssertTrue(normalized.contains("DetailOfflineUnavailablePlaceholder(resource:.taskList)"))
    }

    func testTasksDetailViewShowsOfflineUnavailableBeforeLoadingForUncachedSelection() throws {
        let normalized = try source(named: "Views/Tasks/TasksDetailView.swift")
            .normalizedForSourceAssertions()

        XCTAssertTrue(
            normalized.contains(
                "ifstate.selection!=.none,!canAttemptServerRead,"
                    + "!viewModel.hasCachedSelection(selection:state.selection),"
                    + "state.sections.isEmpty{"
                    + "DetailOfflineUnavailablePlaceholder(resource:.taskList)"
            )
        )
    }

    func testTasksPanelDoesNotReplaceNavigationListWithGlobalLoadErrorPlaceholder() throws {
        let normalized = try source(named: "Views/SidebarPanels/TasksPanel.swift")
            .normalizedForSourceAssertions()

        XCTAssertFalse(normalized.contains("SidebarPanelPlaceholder(title:\"Unabletoloadtasks\""))
    }

    func testFilesPanelOnlyShowsLoadPlaceholderWhenListContentIsEmpty() throws {
        let normalized = try source(named: "Views/SidebarPanels/FilesPanel.swift")
            .normalizedForSourceAssertions()

        XCTAssertTrue(
            normalized.contains(
                "}elseifletmessage=viewModel.listLoadState.errorMessage,"
                    + "viewModel.items.isEmpty{"
            )
        )
    }

    func testChatViewUsesSharedOfflineUnavailablePlaceholder() throws {
        let normalized = try source(named: "Views/Chat/ChatView.swift")
            .normalizedForSourceAssertions()

        XCTAssertTrue(normalized.contains("DetailOfflineUnavailablePlaceholder(resource:.chat)"))
    }

    func testChatViewShowsOfflineUnavailableBeforeLoadingForUncachedSelection() throws {
        let normalized = try source(named: "Views/Chat/ChatView.swift")
            .normalizedForSourceAssertions()

        XCTAssertTrue(
            normalized.contains(
                "elseifshouldShowOfflineUnavailableConversation{"
                    + "DetailOfflineUnavailablePlaceholder(resource:.chat)"
                )
        )
    }

    func testChatViewKeepsComposerVisibleAlongsideOfflineUnavailablePlaceholder() throws {
        let normalized = try source(named: "Views/Chat/ChatView.swift")
            .normalizedForSourceAssertions()

        XCTAssertTrue(
            normalized.contains(
                "elseifshouldShowOfflineUnavailableConversation{"
                    + "DetailOfflineUnavailablePlaceholder(resource:.chat)"
            )
        )
        XCTAssertTrue(
            normalized.contains(
                ".frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)"
                    + "VStack(spacing:8){attachmentsContainer"
                    + "ChatInputBar(text:draftTextBinding,"
            )
        )
    }

    func testTasksStoreShortCircuitsOfflineUnavailableSelectionsBeforeLoading() throws {
        let normalized = try source(named: "Stores/TasksStore.swift")
            .normalizedForSourceAssertions()

        XCTAssertTrue(normalized.contains("if!canAttemptServerRead&&!hasCachedSnapshot{"))
        XCTAssertTrue(normalized.contains("errorMessage=\"Thistasklistisn'tavailableofflineyet.\""))
    }

    func testWebsiteAndFileSelectionViewModelsGuardOfflineUnavailableSelectionsBeforeLoading() throws {
        let websitesNormalized = try source(named: "ViewModels/WebsitesViewModel.swift")
            .normalizedForSourceAssertions()
        let filesNormalized = try source(named: "ViewModels/IngestionViewModel+Public.swift")
            .normalizedForSourceAssertions()

        XCTAssertTrue(
            websitesNormalized.contains(
                "!networkStatus.offlineCapabilityPolicy.canAttemptServerRead,!store.hasCachedDetail(id:id)"
            )
        )
        XCTAssertTrue(
            filesNormalized.contains(
                "!(networkStatus?.offlineCapabilityPolicy.canAttemptServerRead??true),!store.hasCachedMeta(fileId:fileId)"
            )
        )
    }
}

private extension String {
    func normalizedForSourceAssertions() -> String {
        replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }
}

private func source(
    named relativePath: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sideBarRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("sideBar")
    let sourceURL = sideBarRoot.appendingPathComponent(relativePath)

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read \(relativePath): \(error)", file: file, line: line)
        throw error
    }
}
