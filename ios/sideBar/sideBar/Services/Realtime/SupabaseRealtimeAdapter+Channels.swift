import Foundation
import sideBarShared
import OSLog
import Supabase

enum RealtimeSubscriptionDomain: CaseIterable, Equatable {
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
        await tokenStore.set(nextSession.accessToken)
        await client.realtimeV2.setAuth(nextSession.accessToken)
        let plan = Self.makeSubscriptionPlan(
            currentSession: RealtimeSubscriptionSession(
                userId: currentUserId,
                accessToken: currentAccessToken
            ),
            nextSession: nextSession
        ) { [weak self] domain in
            self?.channel(for: domain) != nil
        }
        currentUserId = nextSession.userId
        currentAccessToken = nextSession.accessToken
        for domain in plan.domains {
            await subscribe(to: domain, userId: nextSession.userId)
        }
    }

    func stopInternal() async {
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
}

extension SupabaseRealtimeAdapter {
    func fileJobsFilter(userId: String) -> String {
        "user_id=eq.\(userId)"
    }

    func subscribe(to domain: RealtimeSubscriptionDomain, userId: String) async {
        if let existingChannel = channel(for: domain) {
            await client.realtimeV2.removeChannel(existingChannel)
        }
        clearSubscriptions(for: domain)
        let channel = client.realtimeV2.channel("public:\(domain.table)")
        setSubscriptions(
            registerSubscriptions(for: domain, channel: channel, filter: domain.filter(userId: userId)),
            for: domain
        )
        setChannel(channel, for: domain)
        do {
            try await channel.subscribeWithError()
        } catch is CancellationError {
            // Expected during auth transitions
        } catch {
            clearSubscriptions(for: domain)
            setChannel(nil, for: domain)
            logger.error(
                "\(domain.logLabel, privacy: .public) subscription failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func channel(for domain: RealtimeSubscriptionDomain) -> RealtimeChannelV2? {
        switch domain {
        case .notes:
            notesChannel
        case .websites:
            websitesChannel
        case .ingestedFiles:
            ingestedFilesChannel
        case .fileJobs:
            fileJobsChannel
        case .tasks:
            tasksChannel
        case .taskProjects:
            taskProjectsChannel
        case .taskGroups:
            taskGroupsChannel
        }
    }

    func setChannel(_ channel: RealtimeChannelV2?, for domain: RealtimeSubscriptionDomain) {
        switch domain {
        case .notes:
            notesChannel = channel
        case .websites:
            websitesChannel = channel
        case .ingestedFiles:
            ingestedFilesChannel = channel
        case .fileJobs:
            fileJobsChannel = channel
        case .tasks:
            tasksChannel = channel
        case .taskProjects:
            taskProjectsChannel = channel
        case .taskGroups:
            taskGroupsChannel = channel
        }
    }

    func clearSubscriptions(for domain: RealtimeSubscriptionDomain) {
        switch domain {
        case .notes:
            notesSubscriptions.removeAll()
        case .websites:
            websitesSubscriptions.removeAll()
        case .ingestedFiles:
            ingestedFilesSubscriptions.removeAll()
        case .fileJobs:
            fileJobsSubscriptions.removeAll()
        case .tasks:
            tasksSubscriptions.removeAll()
        case .taskProjects:
            taskProjectsSubscriptions.removeAll()
        case .taskGroups:
            taskGroupsSubscriptions.removeAll()
        }
    }

    func setSubscriptions(_ subscriptions: [ObservationToken], for domain: RealtimeSubscriptionDomain) {
        switch domain {
        case .notes:
            notesSubscriptions = subscriptions
        case .websites:
            websitesSubscriptions = subscriptions
        case .ingestedFiles:
            ingestedFilesSubscriptions = subscriptions
        case .fileJobs:
            fileJobsSubscriptions = subscriptions
        case .tasks:
            tasksSubscriptions = subscriptions
        case .taskProjects:
            taskProjectsSubscriptions = subscriptions
        case .taskGroups:
            taskGroupsSubscriptions = subscriptions
        }
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
