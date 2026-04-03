import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class ChatViewModelTests: ChatViewModelTestCase {
    func testLoadConversationsUsesCacheOnFailure() async {
        let cached = [Conversation(
            id: "conv-1",
            title: "Cached",
            titleGenerated: false,
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-02T00:00:00Z",
            messageCount: 1,
            firstMessage: "Hello",
            isArchived: nil
        )]
        let cache = TestCacheClient()
        cache.set(key: CacheKeys.conversationsList, value: cached, ttlSeconds: CachePolicy.conversationsList)
        let api = ChatViewModelTestsSupport.MockConversationsAPI(listResult: .failure(ChatViewModelTestsSupport.MockError.forced))
        let viewModel = makeViewModel(api: api, cache: cache)
        await viewModel.loadConversations()
        XCTAssertEqual(viewModel.conversations.first?.id, "conv-1")
        XCTAssertNil(viewModel.errorMessage)
    }
    func testHandleToolCallUpdatesStreamingMessage() async {
        let cache = TestCacheClient()
        let conversation = ConversationWithMessages(
            id: "conv-1",
            title: "Chat",
            titleGenerated: false,
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-02T00:00:00Z",
            messageCount: 1,
            firstMessage: nil,
            isArchived: nil,
            messages: [Message(
                id: "assistant-1",
                role: .assistant,
                content: "",
                status: .streaming,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "2026-01-02T00:00:00Z",
                error: nil
            )]
        )
        let api = ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([]), getResult: .success(conversation))
        let viewModel = makeViewModel(api: api, cache: cache)
        await viewModel.selectConversation(id: "conv-1")
        let event = ChatStreamEvent(
            type: .toolCall,
            data: AnyCodable([
                "id": "tool-1",
                "name": "Search",
                "parameters": ["query": "hello"],
                "status": "pending",
                "skill_id": "web-search",
                "icon_key": "web-search"
            ])
        )
        viewModel.handle(event: event)
        let toolCall = viewModel.messages.first?.toolCalls?.first
        XCTAssertEqual(toolCall?.id, "tool-1")
        XCTAssertEqual(toolCall?.name, "Search")
        XCTAssertEqual(toolCall?.status, .pending)
        XCTAssertEqual(toolCall?.skillId, "web-search")
        XCTAssertEqual(toolCall?.iconKey, "web-search")
    }
    func testHandleToolResultPreservesSkillMetadataFromExistingToolCall() async {
        let cache = TestCacheClient()
        let conversation = ConversationWithMessages(
            id: "conv-1",
            title: "Chat",
            titleGenerated: false,
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-02T00:00:00Z",
            messageCount: 1,
            firstMessage: nil,
            isArchived: nil,
            messages: [Message(
                id: "assistant-1",
                role: .assistant,
                content: "",
                status: .streaming,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "2026-01-02T00:00:00Z",
                error: nil
            )]
        )
        let api = ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([]), getResult: .success(conversation))
        let viewModel = makeViewModel(api: api, cache: cache)
        await viewModel.selectConversation(id: "conv-1")
        viewModel.handle(event: ChatStreamEvent(
            type: .toolCall,
            data: AnyCodable([
                "id": "tool-1",
                "name": "Create Note",
                "parameters": [:],
                "status": "pending",
                "skill_id": "notes",
                "icon_key": "notes"
            ])
        ))
        viewModel.handle(event: ChatStreamEvent(
            type: .toolResult,
            data: AnyCodable([
                "id": "tool-1",
                "name": "Create Note",
                "result": ["success": true],
                "status": "success"
            ])
        ))
        let toolCall = viewModel.messages.first?.toolCalls?.first
        XCTAssertEqual(toolCall?.status, .success)
        XCTAssertEqual(toolCall?.skillId, "notes")
        XCTAssertEqual(toolCall?.iconKey, "notes")
    }

    func testNoteCreatedEventRequestsOpeningCreatedNoteInWorkspace() async {
        let cache = TestCacheClient()
        let api = ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([]))
        var requestedNoteID: String?
        let viewModel = makeViewModel(
            api: api,
            cache: cache,
            onOpenNoteRequested: { requestedNoteID = $0 }
        )

        viewModel.handle(event: ChatStreamEvent(
            type: .noteCreated,
            data: AnyCodable([
                "id": "note-1",
                "path": "Folder/Test.md",
                "open_in_workspace": true
            ])
        ))

        XCTAssertEqual(requestedNoteID, "note-1")
    }

    func testHandleToolEndMarksNeedsNewlineAfterSuccessfulToolCompletion() async {
        let cache = TestCacheClient()
        let conversation = ConversationWithMessages(
            id: "conv-1",
            title: "Chat",
            titleGenerated: false,
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-02T00:00:00Z",
            messageCount: 1,
            firstMessage: nil,
            isArchived: nil,
            messages: [Message(
                id: "assistant-1",
                role: .assistant,
                content: "Found this",
                status: .streaming,
                toolCalls: [
                    ToolCall(id: "tool-1", name: "Search", parameters: [:], status: .pending)
                ],
                needsNewline: nil,
                timestamp: "2026-01-02T00:00:00Z",
                error: nil
            )]
        )
        let api = ChatViewModelTestsSupport.MockConversationsAPI(
            listResult: .success([]),
            getResult: .success(conversation)
        )
        let viewModel = makeViewModel(api: api, cache: cache)

        await viewModel.selectConversation(id: "conv-1")
        viewModel.handle(event: ChatStreamEvent(
            type: .toolEnd,
            data: AnyCodable([
                "name": "Search",
                "status": "success"
            ])
        ))

        XCTAssertEqual(viewModel.messages.first?.needsNewline, true)
    }
    func testNoteUpdateClearsCache() async {
        let cache = TestCacheClient()
        let note = NotePayload(id: "note-1", name: "Test.md", content: "Hello", path: "note-1", modified: nil, created: nil)
        cache.set(key: CacheKeys.notesTree, value: FileTree(children: []), ttlSeconds: 60)
        cache.set(key: CacheKeys.note(id: "note-1"), value: note, ttlSeconds: 60)
        let viewModel = makeViewModel(api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])), cache: cache)
        let event = ChatStreamEvent(type: .noteUpdated, data: AnyCodable(["id": "note-1"]))
        viewModel.handle(event: event)
        let cachedNote: NotePayload? = cache.get(key: CacheKeys.note(id: "note-1"))
        let cachedTree: FileTree? = cache.get(key: CacheKeys.notesTree)
        XCTAssertNil(cachedNote)
        XCTAssertNil(cachedTree)
    }
    func testScratchpadUpdateClearsCacheAndBumpsStore() async {
        let cache = TestCacheClient()
        let store = ScratchpadStore()
        let cached = ScratchpadResponse(id: "s1", title: ScratchpadConstants.title, content: "Cached", updatedAt: nil)
        cache.set(key: CacheKeys.scratchpad, value: cached, ttlSeconds: 60)
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache,
            scratchpadStore: store
        )
        let initialVersion = store.version
        let event = ChatStreamEvent(type: .scratchpadUpdated, data: nil)
        viewModel.handle(event: event)
        let cachedScratchpad: ScratchpadResponse? = cache.get(key: CacheKeys.scratchpad)
        XCTAssertNil(cachedScratchpad)
        XCTAssertEqual(store.version, initialVersion + 1)
    }
    func testMemoryEventClearsMemoriesCache() async {
        let cache = TestCacheClient()
        let memory = MemoryItem(
            id: "memory-1",
            path: "memory.md",
            content: "Remember this",
            createdAt: "2026-01-02T00:00:00Z",
            updatedAt: "2026-01-02T00:00:00Z"
        )
        cache.set(key: CacheKeys.memoriesList, value: [memory], ttlSeconds: 60)
        let viewModel = makeViewModel(api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])), cache: cache)
        viewModel.handle(event: ChatStreamEvent(type: .memoryCreated, data: AnyCodable(["id": "memory-1"])))
        let cachedMemories: [MemoryItem]? = cache.get(key: CacheKeys.memoriesList)
        XCTAssertNil(cachedMemories)
    }

    func testStreamEventHandlersBuildOnceAcrossMultipleEvents() {
        let cache = TestCacheClient()
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache
        )

        XCTAssertEqual(viewModel.streamEventHandlersBuildCountForTesting, 0)

        viewModel.handle(event: ChatStreamEvent(type: .scratchpadUpdated, data: nil))
        viewModel.handle(event: ChatStreamEvent(type: .memoryCreated, data: AnyCodable(["id": "memory-1"])))

        XCTAssertEqual(viewModel.streamEventHandlersBuildCountForTesting, 1)
    }

    func testOnboardingStreamEventRequestsOnboardingRefresh() {
        let cache = TestCacheClient()
        var refreshRequestCount = 0
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache,
            onOnboardingStateRefreshRequested: {
                refreshRequestCount += 1
            }
        )

        viewModel.handle(event: ChatStreamEvent(
            type: .onboardingMilestoneCompleted,
            data: AnyCodable([
                "current_onboarding_step": "completed",
                "provider_ready": true,
                "milestone": "secondary_tour_seen"
            ])
        ))

        XCTAssertEqual(refreshRequestCount, 1)
    }

    func testWorkspacePatchEventDispatchesValidatedWorkspaceActions() {
        let cache = TestCacheClient()
        var dispatchedActions: [WorkspaceAction] = []
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache,
            workspaceActionDispatcher: { action in
                dispatchedActions.append(action)
            }
        )
        viewModel.handle(event: ChatStreamEvent(
            type: .workspacePatch,
            data: AnyCodable([
                "version": 1,
                "operations": [
                    ["op": "swap_panes"],
                    ["op": "unknown_op"],
                    [
                        "op": "upsert_agent_surface",
                        "pane": "secondary",
                        "surface": [
                            "type": "map",
                            "surface_id": "surface-map-1",
                            "title": "Delivery map",
                            "payload": [
                                "location": "London",
                                "zoom": 8
                            ],
                            "capabilities": ["can_refresh": false],
                            "is_pinned": true
                        ]
                    ]
                ]
            ])
        ))
        XCTAssertEqual(dispatchedActions.count, 2)
        XCTAssertEqual(dispatchedActions.first, .swapPanes)
        guard case .presentAgentSurface(let surface, let pane) = dispatchedActions[1] else {
            return XCTFail("Expected upsert operation to map to presentAgentSurface")
        }
        XCTAssertEqual(pane, .secondary)
        XCTAssertEqual(surface.type, "map")
        XCTAssertEqual(surface.surfaceId, "surface-map-1")
        XCTAssertEqual(surface.title, "Delivery map")
        XCTAssertEqual(surface.payload["location"], "London")
        XCTAssertEqual(surface.payload["zoom"], "8")
        XCTAssertFalse(surface.capabilities.canRefresh)
        XCTAssertTrue(surface.isPinned)
    }
    func testWorkspacePatchEventRejectsUnsupportedVersion() {
        let cache = TestCacheClient()
        var dispatchedActions: [WorkspaceAction] = []
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache,
            workspaceActionDispatcher: { action in
                dispatchedActions.append(action)
            }
        )
        viewModel.handle(event: ChatStreamEvent(
            type: .workspacePatch,
            data: AnyCodable([
                "version": 2,
                "operations": [["op": "swap_panes"]]
            ])
        ))
        XCTAssertTrue(dispatchedActions.isEmpty)
    }

    func testLoadConversationSortsMessagesByTimestamp() async {
        let cache = TestCacheClient()
        let messages = [
            Message(
                id: "msg-2",
                role: .assistant,
                content: "Second",
                status: .complete,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "2026-01-02T10:00:00Z",
                error: nil
            ),
            Message(
                id: "msg-1",
                role: .user,
                content: "First",
                status: .complete,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "2026-01-02T09:00:00Z",
                error: nil
            )
        ]
        let conversation = ConversationWithMessages(
            id: "conv-1",
            title: "Chat",
            titleGenerated: false,
            createdAt: "2026-01-02T08:00:00Z",
            updatedAt: "2026-01-02T10:00:00Z",
            messageCount: messages.count,
            firstMessage: nil,
            isArchived: nil,
            messages: messages
        )
        let api = ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([]), getResult: .success(conversation))
        let viewModel = makeViewModel(api: api, cache: cache)
        await viewModel.selectConversation(id: "conv-1")
        XCTAssertEqual(viewModel.messages.first?.id, "msg-1")
        XCTAssertEqual(viewModel.messages.last?.id, "msg-2")
    }

    func testSyncSoulCalibrationUsesCurrentOnboardingPrompt() {
        let cache = TestCacheClient()
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache
        )

        viewModel.syncSoulCalibration(
            from: soulCalibrationOnboardingState(
                currentPrompt: .primaryGoal,
                status: .inProgress
            )
        )

        XCTAssertEqual(viewModel.soulCalibrationState?.currentPrompt, .primaryGoal)
    }

    func testSubmitSoulCalibrationAnswerAdvancesPrompt() async throws {
        let cache = TestCacheClient()
        let onboardingAPI = MockOnboardingAPI()
        onboardingAPI.submitCalibrationAnswerResult = .success(
            OnboardingCalibrationActionResponse(
                state: soulCalibrationOnboardingState(
                    currentPrompt: .workingRelationship,
                    status: .inProgress,
                    primaryGoal: "life_admin"
                ),
                calibration: OnboardingCalibrationState(
                    status: .inProgress,
                    currentPrompt: .workingRelationship,
                    answers: OnboardingCalibrationAnswers(
                        primaryGoal: "life_admin",
                        workingRelationship: nil,
                        tonePreferences: nil
                    ),
                    proposedName: nil,
                    completedAt: nil
                ),
                assistantIdentity: nil,
                assistantSoul: nil,
                confirmationText: nil
            )
        )
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache,
            onboardingAPI: onboardingAPI
        )
        viewModel.syncSoulCalibration(
            from: soulCalibrationOnboardingState(
                currentPrompt: .primaryGoal,
                status: .inProgress
            )
        )

        await viewModel.submitSoulCalibrationAnswer(.singleChoice("life_admin"))

        XCTAssertEqual(onboardingAPI.submittedCalibrationAnswers.count, 1)
        XCTAssertEqual(onboardingAPI.submittedCalibrationAnswers.first?.prompt, .primaryGoal)
        XCTAssertEqual(viewModel.soulCalibrationState?.currentPrompt, .workingRelationship)
    }

    func testSubmitSoulCalibrationToneChoicesTransitionsToNameAcceptance() async throws {
        let cache = TestCacheClient()
        let onboardingAPI = MockOnboardingAPI()
        onboardingAPI.submitCalibrationAnswerResult = .success(
            OnboardingCalibrationActionResponse(
                state: soulCalibrationOnboardingState(
                    currentPrompt: .tonePreferences,
                    status: .awaitingNameAcceptance,
                    primaryGoal: "life_admin",
                    workingRelationship: "take_initiative_with_me",
                    tonePreferences: "warm,serious,concise,casual,supportive",
                    proposedName: "Navigator"
                ),
                calibration: OnboardingCalibrationState(
                    status: .awaitingNameAcceptance,
                    currentPrompt: .tonePreferences,
                    answers: OnboardingCalibrationAnswers(
                        primaryGoal: "life_admin",
                        workingRelationship: "take_initiative_with_me",
                        tonePreferences: "warm,serious,concise,casual,supportive"
                    ),
                    proposedName: "Navigator",
                    completedAt: nil
                ),
                assistantIdentity: AssistantIdentitySettings(
                    name: "Navigator",
                    tone: "Warm, serious, concise, casual, supportive",
                    values: "Helpful",
                    boundaries: "Honest"
                ),
                assistantSoul: AssistantSoulSettings(
                    purpose: "Help with life admin",
                    operatingPrinciples: "Stay useful",
                    adaptationPolicy: "Adjust initiative",
                    successSignals: "User feels on top of things"
                ),
                confirmationText: "I think Navigator fits."
            )
        )
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache,
            onboardingAPI: onboardingAPI
        )
        viewModel.syncSoulCalibration(
            from: soulCalibrationOnboardingState(
                currentPrompt: .tonePreferences,
                status: .inProgress,
                primaryGoal: "life_admin",
                workingRelationship: "take_initiative_with_me"
            )
        )

        await viewModel.submitSoulCalibrationAnswer(
            .multipleChoice(["warm", "serious", "concise", "casual", "supportive"])
        )

        XCTAssertEqual(onboardingAPI.submittedCalibrationAnswers.first?.prompt, .tonePreferences)
        XCTAssertEqual(viewModel.soulCalibrationState?.status, .awaitingNameAcceptance)
        XCTAssertEqual(viewModel.soulCalibrationState?.proposedName, "Navigator")
    }

    func testSubmitSoulCalibrationAnswerUsesExplicitPromptWhenRevisitingEarlierStep() async throws {
        let cache = TestCacheClient()
        let onboardingAPI = MockOnboardingAPI()
        onboardingAPI.submitCalibrationAnswerResult = .success(
            OnboardingCalibrationActionResponse(
                state: soulCalibrationOnboardingState(
                    currentPrompt: .tonePreferences,
                    status: .inProgress,
                    primaryGoal: "life_admin",
                    workingRelationship: "take_initiative_with_me"
                ),
                calibration: OnboardingCalibrationState(
                    status: .inProgress,
                    currentPrompt: .tonePreferences,
                    answers: OnboardingCalibrationAnswers(
                        primaryGoal: "life_admin",
                        workingRelationship: "take_initiative_with_me",
                        tonePreferences: nil
                    ),
                    proposedName: nil,
                    completedAt: nil
                ),
                assistantIdentity: nil,
                assistantSoul: nil,
                confirmationText: "How should I sound when we work together?"
            )
        )
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache,
            onboardingAPI: onboardingAPI
        )
        viewModel.syncSoulCalibration(
            from: soulCalibrationOnboardingState(
                currentPrompt: .tonePreferences,
                status: .inProgress,
                primaryGoal: "life_admin",
                workingRelationship: "keep_me_on_track",
                tonePreferences: "warm,serious,concise,casual,supportive"
            )
        )

        await viewModel.submitSoulCalibrationAnswer(
            prompt: .workingRelationship,
            .singleChoice("take_initiative_with_me")
        )

        XCTAssertEqual(onboardingAPI.submittedCalibrationAnswers.count, 1)
        XCTAssertEqual(
            onboardingAPI.submittedCalibrationAnswers.first?.prompt,
            .workingRelationship
        )
        XCTAssertEqual(
            onboardingAPI.submittedCalibrationAnswers.first?.answer,
            .singleChoice("take_initiative_with_me")
        )
    }

    func testSubmitSoulCalibrationAnswerQueuesOptimisticNextStepWhilePreviousStepIsInFlight() async throws {
        let cache = TestCacheClient()
        let onboardingAPI = DelayedOnboardingAPI()
        onboardingAPI.shouldSuspendSubmitUntilResumed = true
        onboardingAPI.submitCalibrationAnswerResults = [
            .success(
                OnboardingCalibrationActionResponse(
                    state: soulCalibrationOnboardingState(
                        currentPrompt: .workingRelationship,
                        status: .inProgress,
                        primaryGoal: "life_admin"
                    ),
                    calibration: OnboardingCalibrationState(
                        status: .inProgress,
                        currentPrompt: .workingRelationship,
                        answers: OnboardingCalibrationAnswers(
                            primaryGoal: "life_admin",
                            workingRelationship: nil,
                            tonePreferences: nil
                        ),
                        proposedName: nil,
                        completedAt: nil
                    ),
                    assistantIdentity: nil,
                    assistantSoul: AssistantSoulSettings(
                        purpose: "Help with life admin",
                        operatingPrinciples: nil,
                        adaptationPolicy: nil,
                        successSignals: nil
                    ),
                    confirmationText: nil
                )
            ),
            .success(
                OnboardingCalibrationActionResponse(
                    state: soulCalibrationOnboardingState(
                        currentPrompt: .tonePreferences,
                        status: .inProgress,
                        primaryGoal: "life_admin",
                        workingRelationship: "keep_me_on_track"
                    ),
                    calibration: OnboardingCalibrationState(
                        status: .inProgress,
                        currentPrompt: .tonePreferences,
                        answers: OnboardingCalibrationAnswers(
                            primaryGoal: "life_admin",
                            workingRelationship: "keep_me_on_track",
                            tonePreferences: nil
                        ),
                        proposedName: nil,
                        completedAt: nil
                    ),
                    assistantIdentity: nil,
                    assistantSoul: AssistantSoulSettings(
                        purpose: "Help with life admin",
                        operatingPrinciples: "Keep momentum visible.",
                        adaptationPolicy: "Adapt to durable preferences.",
                        successSignals: "More follow-through."
                    ),
                    confirmationText: nil
                )
            )
        ]
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache,
            onboardingAPI: onboardingAPI
        )
        viewModel.syncSoulCalibration(
            from: soulCalibrationOnboardingState(
                currentPrompt: .primaryGoal,
                status: .inProgress
            )
        )

        let firstSubmitStarted = expectation(description: "first calibration submit started")
        var didObserveFirstSubmitStart = false
        onboardingAPI.onSubmitStarted = {
            guard !didObserveFirstSubmitStart else {
                return
            }
            didObserveFirstSubmitStart = true
            firstSubmitStarted.fulfill()
        }

        let firstSubmit = Task {
            await viewModel.submitSoulCalibrationAnswer(
                prompt: .primaryGoal,
                .singleChoice("life_admin")
            )
        }
        await fulfillment(of: [firstSubmitStarted], timeout: 1.0)

        let secondSubmit = Task {
            await viewModel.submitSoulCalibrationAnswer(
                prompt: .workingRelationship,
                .singleChoice("keep_me_on_track")
            )
        }
        await Task.yield()
        onboardingAPI.shouldSuspendSubmitUntilResumed = false
        onboardingAPI.resumeSubmit()

        _ = await firstSubmit.value
        _ = await secondSubmit.value

        XCTAssertEqual(
            onboardingAPI.submittedCalibrationAnswers.map(\.prompt),
            [.primaryGoal, .workingRelationship]
        )
        XCTAssertEqual(viewModel.soulCalibrationState?.currentPrompt, .tonePreferences)
    }

    func testAcceptSoulCalibrationNameClearsStateAndAllowsDiscovery() async throws {
        let cache = TestCacheClient()
        let onboardingAPI = MockOnboardingAPI()
        onboardingAPI.acceptCalibrationNameResult = .success(
            OnboardingCalibrationActionResponse(
                state: OnboardingState(
                    status: .inProgress,
                    providerReady: true,
                    currentOnboardingStep: .featureDiscovery,
                    isOnboardingComplete: false,
                    intent: .chat,
                    calibration: OnboardingCalibrationState(
                        status: .completed,
                        currentPrompt: .tonePreferences,
                        answers: OnboardingCalibrationAnswers(
                            primaryGoal: "life_admin",
                            workingRelationship: "take_initiative_with_me",
                            tonePreferences: "warm,serious,concise,casual,supportive"
                        ),
                        proposedName: "Navigator",
                        completedAt: "2026-04-02T12:00:00Z"
                    ),
                    milestones: OnboardingMilestones(
                        providerConnected: "2026-04-02T11:00:00Z",
                        firstOutcomeCompleted: nil,
                        profileBasicsSet: nil,
                        communicationStyleSet: nil,
                        secondaryTourSeen: nil
                    ),
                    permissions: OnboardingPermissions(location: .granted, notifications: .granted),
                    lastPromptedAt: nil
                ),
                calibration: OnboardingCalibrationState(
                    status: .completed,
                    currentPrompt: .tonePreferences,
                    answers: OnboardingCalibrationAnswers(
                        primaryGoal: "life_admin",
                        workingRelationship: "take_initiative_with_me",
                        tonePreferences: "warm,serious,concise,casual,supportive"
                    ),
                    proposedName: "Navigator",
                    completedAt: "2026-04-02T12:00:00Z"
                ),
                assistantIdentity: AssistantIdentitySettings(
                    name: "Navigator",
                    tone: "Warm, serious, concise, casual, supportive",
                    values: "Helpful",
                    boundaries: "Honest"
                ),
                assistantSoul: AssistantSoulSettings(
                    purpose: "Help with life admin",
                    operatingPrinciples: "Stay useful",
                    adaptationPolicy: "Adjust initiative",
                    successSignals: "User feels on top of things"
                ),
                confirmationText: "Navigator it is."
            )
        )
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache,
            onboardingAPI: onboardingAPI
        )
        viewModel.syncSoulCalibration(
            from: soulCalibrationOnboardingState(
                currentPrompt: .tonePreferences,
                status: .awaitingNameAcceptance,
                primaryGoal: "life_admin",
                workingRelationship: "take_initiative_with_me",
                tonePreferences: "warm,serious,concise,casual,supportive",
                proposedName: "Navigator"
            )
        )

        await viewModel.acceptSoulCalibrationName()

        XCTAssertEqual(onboardingAPI.acceptCalibrationNameCallCount, 1)
        XCTAssertNil(viewModel.soulCalibrationState)
        XCTAssertTrue(viewModel.canShowFeatureDiscovery)
    }

    private func soulCalibrationOnboardingState(
        currentPrompt: OnboardingCalibrationPrompt,
        status: OnboardingCalibrationStatus,
        primaryGoal: String? = nil,
        workingRelationship: String? = nil,
        tonePreferences: String? = nil,
        proposedName: String? = nil
    ) -> OnboardingState {
        OnboardingState(
            status: .inProgress,
            providerReady: true,
            currentOnboardingStep: .soulCalibration,
            isOnboardingComplete: false,
            intent: .chat,
            calibration: OnboardingCalibrationState(
                status: status,
                currentPrompt: currentPrompt,
                answers: OnboardingCalibrationAnswers(
                    primaryGoal: primaryGoal,
                    workingRelationship: workingRelationship,
                    tonePreferences: tonePreferences
                ),
                proposedName: proposedName,
                completedAt: nil
            ),
            milestones: OnboardingMilestones(
                providerConnected: "2026-04-02T11:00:00Z",
                firstOutcomeCompleted: nil,
                profileBasicsSet: nil,
                communicationStyleSet: nil,
                secondaryTourSeen: nil
            ),
            permissions: OnboardingPermissions(location: .granted, notifications: .granted),
            lastPromptedAt: nil
        )
    }
}
