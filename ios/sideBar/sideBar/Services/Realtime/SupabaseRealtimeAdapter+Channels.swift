import Foundation
import sideBarShared
import OSLog
import Realtime
import Supabase

extension SupabaseRealtimeAdapter {
    func startInternal(userId: String, accessToken: String?) async {
        await tokenStore.set(accessToken)
        await client.realtimeV2.setAuth(accessToken)
        let shouldResubscribeNotes = currentUserId != userId || notesChannel == nil
        let shouldResubscribeWebsites = currentUserId != userId || websitesChannel == nil
        let shouldResubscribeIngestedFiles = currentUserId != userId || ingestedFilesChannel == nil
        let shouldResubscribeFileJobs = currentUserId != userId || fileJobsChannel == nil
        currentUserId = userId
        if shouldResubscribeNotes {
            await subscribeToNotes(userId: userId)
        }
        if shouldResubscribeWebsites {
            await subscribeToWebsites(userId: userId)
        }
        if shouldResubscribeIngestedFiles {
            await subscribeToIngestedFiles(userId: userId)
        }
        if shouldResubscribeFileJobs {
            await subscribeToFileJobs()
        }
    }

    func stopInternal() async {
        notesSubscriptions.removeAll()
        websitesSubscriptions.removeAll()
        ingestedFilesSubscriptions.removeAll()
        fileJobsSubscriptions.removeAll()
        let channels: [RealtimeChannelV2] = [
            notesChannel,
            websitesChannel,
            ingestedFilesChannel,
            fileJobsChannel
        ].compactMap { $0 }
        notesChannel = nil
        websitesChannel = nil
        ingestedFilesChannel = nil
        fileJobsChannel = nil
        await tokenStore.set(nil)
        currentUserId = nil
        for channel in channels {
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
}

extension SupabaseRealtimeAdapter {
    func subscribeToNotes(userId: String) async {
        if let existingChannel = notesChannel {
            await client.realtimeV2.removeChannel(existingChannel)
        }
        notesSubscriptions.removeAll()
        let channel = client.realtimeV2.channel("public:\(RealtimeTable.notes)")
        let filter = "user_id=eq.\(userId)"
        notesSubscriptions.append(
            channel.onPostgresChange(
                InsertAction.self,
                schema: "public",
                table: RealtimeTable.notes,
                filter: filter
            ) { [weak self] action in
                Task { @MainActor [weak self] in
                    self?.handleNoteInsert(SupabaseInsertActionAdapter(action: action))
                }
            }
        )
        notesSubscriptions.append(
            channel.onPostgresChange(
                UpdateAction.self,
                schema: "public",
                table: RealtimeTable.notes,
                filter: filter
            ) { [weak self] action in
                Task { @MainActor [weak self] in
                    self?.handleNoteUpdate(SupabaseUpdateActionAdapter(action: action))
                }
            }
        )
        notesSubscriptions.append(
            channel.onPostgresChange(
                DeleteAction.self,
                schema: "public",
                table: RealtimeTable.notes,
                filter: filter
            ) { [weak self] action in
                Task { @MainActor [weak self] in
                    self?.handleNoteDelete(SupabaseDeleteActionAdapter(action: action))
                }
            }
        )
        notesChannel = channel
        do {
            try await channel.subscribeWithError()
        } catch is CancellationError {
            // Expected during auth transitions
        } catch {
            logger.error("Notes subscription failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func subscribeToWebsites(userId: String) async {
        if let existingChannel = websitesChannel {
            await client.realtimeV2.removeChannel(existingChannel)
        }
        websitesSubscriptions.removeAll()
        let channel = client.realtimeV2.channel("public:\(RealtimeTable.websites)")
        let filter = "user_id=eq.\(userId)"
        websitesSubscriptions.append(
            channel.onPostgresChange(
                InsertAction.self,
                schema: "public",
                table: RealtimeTable.websites,
                filter: filter
            ) { [weak self] action in
                Task { @MainActor [weak self] in
                    self?.handleWebsiteInsert(SupabaseInsertActionAdapter(action: action))
                }
            }
        )
        websitesSubscriptions.append(
            channel.onPostgresChange(
                UpdateAction.self,
                schema: "public",
                table: RealtimeTable.websites,
                filter: filter
            ) { [weak self] action in
                Task { @MainActor [weak self] in
                    self?.handleWebsiteUpdate(SupabaseUpdateActionAdapter(action: action))
                }
            }
        )
        websitesSubscriptions.append(
            channel.onPostgresChange(
                DeleteAction.self,
                schema: "public",
                table: RealtimeTable.websites,
                filter: filter
            ) { [weak self] action in
                Task { @MainActor [weak self] in
                    self?.handleWebsiteDelete(SupabaseDeleteActionAdapter(action: action))
                }
            }
        )
        websitesChannel = channel
        do {
            try await channel.subscribeWithError()
        } catch is CancellationError {
            // Expected during auth transitions
        } catch {
            logger.error("Websites subscription failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func subscribeToIngestedFiles(userId: String) async {
        if let existingChannel = ingestedFilesChannel {
            await client.realtimeV2.removeChannel(existingChannel)
        }
        ingestedFilesSubscriptions.removeAll()
        let channel = client.realtimeV2.channel("public:\(RealtimeTable.ingestedFiles)")
        let filter = "user_id=eq.\(userId)"
        ingestedFilesSubscriptions.append(
            channel.onPostgresChange(
                InsertAction.self,
                schema: "public",
                table: RealtimeTable.ingestedFiles,
                filter: filter
            ) { [weak self] action in
                Task { @MainActor [weak self] in
                    self?.handleIngestedFileInsert(SupabaseInsertActionAdapter(action: action))
                }
            }
        )
        ingestedFilesSubscriptions.append(
            channel.onPostgresChange(
                UpdateAction.self,
                schema: "public",
                table: RealtimeTable.ingestedFiles,
                filter: filter
            ) { [weak self] action in
                Task { @MainActor [weak self] in
                    self?.handleIngestedFileUpdate(SupabaseUpdateActionAdapter(action: action))
                }
            }
        )
        ingestedFilesSubscriptions.append(
            channel.onPostgresChange(
                DeleteAction.self,
                schema: "public",
                table: RealtimeTable.ingestedFiles,
                filter: filter
            ) { [weak self] action in
                Task { @MainActor [weak self] in
                    self?.handleIngestedFileDelete(SupabaseDeleteActionAdapter(action: action))
                }
            }
        )
        ingestedFilesChannel = channel
        do {
            try await channel.subscribeWithError()
        } catch is CancellationError {
            // Expected during auth transitions
        } catch {
            logger.error("Ingested files subscription failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func subscribeToFileJobs() async {
        if let existingChannel = fileJobsChannel {
            await client.realtimeV2.removeChannel(existingChannel)
        }
        fileJobsSubscriptions.removeAll()
        let channel = client.realtimeV2.channel("public:\(RealtimeTable.fileJobs)")
        fileJobsSubscriptions.append(
            channel.onPostgresChange(
                InsertAction.self,
                schema: "public",
                table: RealtimeTable.fileJobs
            ) { [weak self] action in
                Task { @MainActor [weak self] in
                    self?.handleFileJobInsert(SupabaseInsertActionAdapter(action: action))
                }
            }
        )
        fileJobsSubscriptions.append(
            channel.onPostgresChange(
                UpdateAction.self,
                schema: "public",
                table: RealtimeTable.fileJobs
            ) { [weak self] action in
                Task { @MainActor [weak self] in
                    self?.handleFileJobUpdate(SupabaseUpdateActionAdapter(action: action))
                }
            }
        )
        fileJobsSubscriptions.append(
            channel.onPostgresChange(
                DeleteAction.self,
                schema: "public",
                table: RealtimeTable.fileJobs
            ) { [weak self] action in
                Task { @MainActor [weak self] in
                    self?.handleFileJobDelete(SupabaseDeleteActionAdapter(action: action))
                }
            }
        )
        fileJobsChannel = channel
        do {
            try await channel.subscribeWithError()
        } catch is CancellationError {
            // Expected during auth transitions
        } catch {
            logger.error("File jobs subscription failed: \(error.localizedDescription, privacy: .public)")
        }
    }

}
