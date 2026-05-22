import Foundation
import sideBarShared
import OSLog
import Supabase

enum RealtimeSubscriptionDomain: CaseIterable, Equatable, Hashable {
    case notes
    case websites
    case ingestedFiles
    case fileJobs
    case tasks
    case taskProjects
    case taskGroups

    var table: String {
        switch self {
        case .notes:
            RealtimeTable.notes
        case .websites:
            RealtimeTable.websites
        case .ingestedFiles:
            RealtimeTable.ingestedFiles
        case .fileJobs:
            RealtimeTable.fileJobs
        case .tasks:
            RealtimeTable.tasks
        case .taskProjects:
            RealtimeTable.taskProjects
        case .taskGroups:
            RealtimeTable.taskGroups
        }
    }

    var logLabel: String {
        switch self {
        case .notes:
            "Notes"
        case .websites:
            "Websites"
        case .ingestedFiles:
            "Ingested files"
        case .fileJobs:
            "File jobs"
        case .tasks:
            "Tasks"
        case .taskProjects:
            "Task projects"
        case .taskGroups:
            "Task groups"
        }
    }

    func filter(userId: String) -> String {
        "user_id=eq.\(userId)"
    }
}

struct RealtimeSubscriptionSession: Equatable {
    let userId: String
    let accessToken: String

    init?(userId: String?, accessToken: String?) {
        guard let userId = userId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !userId.isEmpty,
              let accessToken,
              !accessToken.isEmpty
        else {
            return nil
        }
        self.userId = userId
        self.accessToken = accessToken
    }
}

struct RealtimeSubscriptionPlan: Equatable {
    let domains: [RealtimeSubscriptionDomain]
}

struct RealtimeSubscriptionSlot {
    var channel: RealtimeChannelV2?
    var subscribedSession: RealtimeSubscriptionSession?
    var subscriptions: [ObservationToken] = []
}

struct RealtimeSubscriptionHandlers {
    let onInsert: @MainActor (InsertAction) -> Void
    let onUpdate: @MainActor (UpdateAction) -> Void
    let onDelete: @MainActor (DeleteAction) -> Void
}

extension SupabaseRealtimeAdapter {
    func startInternal(userId: String, accessToken: String?) async {
        guard let nextSession = RealtimeSubscriptionSession(userId: userId, accessToken: accessToken) else {
            await stopInternal()
            return
        }
        let currentSession = RealtimeSubscriptionSession(
            userId: currentUserId,
            accessToken: currentAccessToken
        )
        let plan = Self.makeSubscriptionPlan(
            currentSession: currentSession,
            nextSession: nextSession
        ) { [weak self] domain in
            self?.channel(for: domain) != nil
        }
        if Self.shouldClearRealtimeHealthBeforeAuthUpdate(plan: plan) {
            setRealtimeConnected(false)
        }
        await tokenStore.set(nextSession.accessToken)
        await client.realtimeV2.setAuth(nextSession.accessToken)
        currentUserId = nextSession.userId
        currentAccessToken = nextSession.accessToken
        for domain in plan.domains {
            await subscribe(to: domain, session: nextSession)
        }
        updateRealtimeConnectionState()
    }

    func stopInternal() async {
        setRealtimeConnected(false)
        let channels = RealtimeSubscriptionDomain.allCases.compactMap { channel(for: $0) }
        for domain in RealtimeSubscriptionDomain.allCases {
            clearSubscriptions(for: domain)
            setChannel(nil, for: domain)
        }
        await tokenStore.set(nil)
        currentUserId = nil
        currentAccessToken = nil
        for channel in channels {
            guard client.realtimeV2.channels[channel.topic] != nil else { continue }
            await client.realtimeV2.removeChannel(channel)
        }
    }

    func enqueueTransition(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let previous = transitionTask
        let task = Task { @MainActor in
            if let previous {
                await previous.value
            }
            await operation()
        }
        transitionTask = task
        return task
    }

    static func makeSubscriptionPlan(
        currentSession: RealtimeSubscriptionSession?,
        nextSession: RealtimeSubscriptionSession,
        hasChannel: (RealtimeSubscriptionDomain) -> Bool
    ) -> RealtimeSubscriptionPlan {
        let domains = RealtimeSubscriptionDomain.allCases.filter { domain in
            shouldResubscribeChannel(
                currentSession: currentSession,
                nextSession: nextSession,
                hasChannel: hasChannel(domain)
            )
        }
        return RealtimeSubscriptionPlan(domains: domains)
    }

    static func shouldClearRealtimeHealthBeforeAuthUpdate(plan: RealtimeSubscriptionPlan) -> Bool {
        !plan.domains.isEmpty
    }
}

extension SupabaseRealtimeAdapter {
    func fileJobsFilter(userId: String) -> String {
        "user_id=eq.\(userId)"
    }

    func subscribe(to domain: RealtimeSubscriptionDomain, session: RealtimeSubscriptionSession) async {
        if let existingChannel = channel(for: domain) {
            await client.realtimeV2.removeChannel(existingChannel)
        }
        clearSubscriptions(for: domain)
        let channel = client.realtimeV2.channel("public:\(domain.table)")
        setSubscriptions(
            registerSubscriptions(for: domain, channel: channel, filter: domain.filter(userId: session.userId)),
            for: domain
        )
        setChannel(channel, for: domain, subscribedSession: nil)
        do {
            try await channel.subscribeWithError()
        } catch is CancellationError {
            // Expected during auth transitions
            markRealtimeSubscriptionFailed(for: domain)
            return
        } catch {
            markRealtimeSubscriptionFailed(for: domain)
            logger.error(
                "\(domain.logLabel, privacy: .public) subscription failed: \(error.localizedDescription, privacy: .public)"
            )
            return
        }
        setChannel(channel, for: domain, subscribedSession: session)
        updateRealtimeConnectionState()
    }

    func markRealtimeSubscriptionFailed(for domain: RealtimeSubscriptionDomain) {
        clearSubscriptions(for: domain)
        setChannel(nil, for: domain)
        setRealtimeConnected(false)
    }

    func channel(for domain: RealtimeSubscriptionDomain) -> RealtimeChannelV2? {
        subscriptionSlots[domain]?.channel
    }

    func setChannel(_ channel: RealtimeChannelV2?, for domain: RealtimeSubscriptionDomain) {
        setChannel(
            channel,
            for: domain,
            subscribedSession: RealtimeSubscriptionSession(
                userId: currentUserId,
                accessToken: currentAccessToken
            )
        )
    }

    func setChannel(
        _ channel: RealtimeChannelV2?,
        for domain: RealtimeSubscriptionDomain,
        subscribedSession: RealtimeSubscriptionSession?
    ) {
        var slot = subscriptionSlots[domain] ?? RealtimeSubscriptionSlot()
        slot.channel = channel
        slot.subscribedSession = channel == nil ? nil : subscribedSession
        subscriptionSlots[domain] = slot
    }

    func clearSubscriptions(for domain: RealtimeSubscriptionDomain) {
        setSubscriptions([], for: domain)
    }

    func subscriptions(for domain: RealtimeSubscriptionDomain) -> [ObservationToken] {
        subscriptionSlots[domain]?.subscriptions ?? []
    }

    func setSubscriptions(_ subscriptions: [ObservationToken], for domain: RealtimeSubscriptionDomain) {
        var slot = subscriptionSlots[domain] ?? RealtimeSubscriptionSlot()
        slot.subscriptions = subscriptions
        subscriptionSlots[domain] = slot
    }

    func registerSubscriptions(
        for domain: RealtimeSubscriptionDomain,
        channel: RealtimeChannelV2,
        filter: String
    ) -> [ObservationToken] {
        let handlers = subscriptionHandlers(for: domain)
        return registerChangeHandlers(
            channel: channel,
            table: domain.table,
            filter: filter,
            onInsert: handlers.onInsert,
            onUpdate: handlers.onUpdate,
            onDelete: handlers.onDelete
        )
    }

    func subscriptionHandlers(for domain: RealtimeSubscriptionDomain) -> RealtimeSubscriptionHandlers {
        switch domain {
        case .notes, .websites, .ingestedFiles, .fileJobs:
            contentSubscriptionHandlers(for: domain)
        case .tasks, .taskProjects, .taskGroups:
            taskSubscriptionHandlers(for: domain)
        }
    }

    func contentSubscriptionHandlers(for domain: RealtimeSubscriptionDomain) -> RealtimeSubscriptionHandlers {
        switch domain {
        case .notes:
            return RealtimeSubscriptionHandlers(
                onInsert: { [weak self] action in
                    self?.handleNoteInsert(SupabaseInsertActionAdapter(action: action))
                },
                onUpdate: { [weak self] action in
                    self?.handleNoteUpdate(SupabaseUpdateActionAdapter(action: action))
                },
                onDelete: { [weak self] action in
                    self?.handleNoteDelete(SupabaseDeleteActionAdapter(action: action))
                }
            )
        case .websites:
            return RealtimeSubscriptionHandlers(
                onInsert: { [weak self] action in
                    self?.handleWebsiteInsert(SupabaseInsertActionAdapter(action: action))
                },
                onUpdate: { [weak self] action in
                    self?.handleWebsiteUpdate(SupabaseUpdateActionAdapter(action: action))
                },
                onDelete: { [weak self] action in
                    self?.handleWebsiteDelete(SupabaseDeleteActionAdapter(action: action))
                }
            )
        case .ingestedFiles:
            return RealtimeSubscriptionHandlers(
                onInsert: { [weak self] action in
                    self?.handleIngestedFileInsert(SupabaseInsertActionAdapter(action: action))
                },
                onUpdate: { [weak self] action in
                    self?.handleIngestedFileUpdate(SupabaseUpdateActionAdapter(action: action))
                },
                onDelete: { [weak self] action in
                    self?.handleIngestedFileDelete(SupabaseDeleteActionAdapter(action: action))
                }
            )
        case .fileJobs:
            return RealtimeSubscriptionHandlers(
                onInsert: { [weak self] action in
                    self?.handleFileJobInsert(SupabaseInsertActionAdapter(action: action))
                },
                onUpdate: { [weak self] action in
                    self?.handleFileJobUpdate(SupabaseUpdateActionAdapter(action: action))
                },
                onDelete: { [weak self] action in
                    self?.handleFileJobDelete(SupabaseDeleteActionAdapter(action: action))
                }
            )
        case .tasks, .taskProjects, .taskGroups:
            preconditionFailure("Task realtime domains are handled separately")
        }
    }

    func taskSubscriptionHandlers(for domain: RealtimeSubscriptionDomain) -> RealtimeSubscriptionHandlers {
        switch domain {
        case .tasks:
            return RealtimeSubscriptionHandlers(
                onInsert: { [weak self] action in
                    self?.handleTaskInsert(SupabaseInsertActionAdapter(action: action))
                },
                onUpdate: { [weak self] action in
                    self?.handleTaskUpdate(SupabaseUpdateActionAdapter(action: action))
                },
                onDelete: { [weak self] action in
                    self?.handleTaskDelete(SupabaseDeleteActionAdapter(action: action))
                }
            )
        case .taskProjects:
            return RealtimeSubscriptionHandlers(
                onInsert: { [weak self] action in
                    self?.handleTaskProjectInsert(SupabaseInsertActionAdapter(action: action))
                },
                onUpdate: { [weak self] action in
                    self?.handleTaskProjectUpdate(SupabaseUpdateActionAdapter(action: action))
                },
                onDelete: { [weak self] action in
                    self?.handleTaskProjectDelete(SupabaseDeleteActionAdapter(action: action))
                }
            )
        case .taskGroups:
            return RealtimeSubscriptionHandlers(
                onInsert: { [weak self] action in
                    self?.handleTaskGroupInsert(SupabaseInsertActionAdapter(action: action))
                },
                onUpdate: { [weak self] action in
                    self?.handleTaskGroupUpdate(SupabaseUpdateActionAdapter(action: action))
                },
                onDelete: { [weak self] action in
                    self?.handleTaskGroupDelete(SupabaseDeleteActionAdapter(action: action))
                }
            )
        case .notes, .websites, .ingestedFiles, .fileJobs:
            preconditionFailure("Content realtime domains are handled separately")
        }
    }

    func registerChangeHandlers(
        channel: RealtimeChannelV2,
        table: String,
        filter: String,
        onInsert: @escaping @MainActor (InsertAction) -> Void,
        onUpdate: @escaping @MainActor (UpdateAction) -> Void,
        onDelete: @escaping @MainActor (DeleteAction) -> Void
    ) -> [ObservationToken] {
        [
            channel.onPostgresChange(
                InsertAction.self,
                schema: "public",
                table: table,
                filter: filter
            ) { action in
                Task { @MainActor in
                    onInsert(action)
                }
            },
            channel.onPostgresChange(
                UpdateAction.self,
                schema: "public",
                table: table,
                filter: filter
            ) { action in
                Task { @MainActor in
                    onUpdate(action)
                }
            },
            channel.onPostgresChange(
                DeleteAction.self,
                schema: "public",
                table: table,
                filter: filter
            ) { action in
                Task { @MainActor in
                    onDelete(action)
                }
            }
        ]
    }
}
