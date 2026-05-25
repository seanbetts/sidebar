import CoreData
import Foundation
import OSLog
import sideBarShared

private struct HeaderQueueState {
    let pendingCount: Int
    let failedCount: Int
    let failedRows: [PendingWriteSummary]
}

@MainActor
extension WriteQueue {
    var headerStatusSnapshot: HeaderSyncStatusSnapshot? {
        if !failedHeaderRows.isEmpty {
            return .error(rows: failedHeaderRows.map(makeHeaderRow))
        }

        if isExecutingWrite {
            return .syncing
        }

        if activePendingCount > 0 {
            return .pending
        }

        return nil
    }

    func retryWrite(id: UUID) async throws {
        try await runHeaderBackgroundTask { context in
            let request = PendingWrite.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            guard let write = try context.fetch(request).first else { return }
            write.status = WriteQueueStatus.pending.rawValue
            write.attempts = 0
            write.lastError = nil
            write.lastAttemptAt = nil
            write.conflictReason = nil
        }

        await refreshHeaderState()
        await processRetriedWrite(id: id)
        await refreshHeaderState()
    }

    func cancelWrite(id: UUID) async throws {
        try await runHeaderBackgroundTask { context in
            let request = PendingWrite.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            guard let write = try context.fetch(request).first else { return }
            context.delete(write)
        }

        await refreshHeaderState()
    }

    func fetchFailedHeaderRows() async throws -> [PendingWriteSummary] {
        try await runHeaderBackgroundTask { context in
            let request = PendingWrite.fetchRequest()
            request.predicate = NSPredicate(format: "status == %@", WriteQueueStatus.failed.rawValue)
            request.sortDescriptors = [
                NSSortDescriptor(keyPath: \PendingWrite.createdAt, ascending: true)
            ]
            return try context.fetch(request).map(PendingWriteQueueMapper.summary)
        }
    }

    private func makeHeaderRow(summary: PendingWriteSummary) -> HeaderStatusRowModel {
        HeaderStatusRowModel(
            tone: .error,
            id: summary.id.uuidString,
            title: headerTitle(for: summary),
            detail: headerDetail(for: summary),
            actions: [
                HeaderStatusActionModel(id: "retry", title: "Retry", role: .default),
                HeaderStatusActionModel(id: "cancel", title: "Cancel", role: .destructive)
            ]
        )
    }

    private func headerTitle(for summary: PendingWriteSummary) -> String {
        let operation = summary.operationType.replacingOccurrences(of: "_", with: " ").capitalized
        let entity = summary.entityType.replacingOccurrences(of: "_", with: " ").lowercased()
        return "\(operation) \(entity)"
    }

    private func headerDetail(for summary: PendingWriteSummary) -> String? {
        if let conflictReason = summary.conflictReason?.trimmingCharacters(in: .whitespacesAndNewlines),
           !conflictReason.isEmpty {
            return conflictReason
        }

        guard let lastError = summary.lastError?.trimmingCharacters(in: .whitespacesAndNewlines),
              !lastError.isEmpty else {
            return nil
        }

        if let apiError = storedAPIClientError(from: lastError) {
            return ErrorMapping.message(for: apiError)
        }

        return lastError
    }

    private func storedAPIClientError(from description: String) -> APIClientError? {
        switch description {
        case "invalidUrl":
            return .invalidUrl
        case "missingToken":
            return .missingToken
        case "decodingFailed":
            return .decodingFailed
        case "unknown":
            return .unknown
        default:
            break
        }

        if description.hasPrefix("requestFailed("), description.hasSuffix(")"),
           let status = Int(description.dropFirst("requestFailed(".count).dropLast()) {
            return .requestFailed(status)
        }

        if description.hasPrefix("apiError(\""), description.hasSuffix("\")") {
            let quotedMessage = description
                .dropFirst("apiError(\"".count)
                .dropLast(2)
            let message = quotedMessage.replacingOccurrences(of: "\\\"", with: "\"")
            return .apiError(message)
        }

        return nil
    }

    private func refreshHeaderState() async {
        do {
            let snapshot = try await runHeaderBackgroundTask { context -> HeaderQueueState in
                let queuedRequest = PendingWrite.fetchRequest()
                let failedRequest = PendingWrite.fetchRequest()
                failedRequest.predicate = NSPredicate(format: "status == %@", WriteQueueStatus.failed.rawValue)
                failedRequest.sortDescriptors = [
                    NSSortDescriptor(keyPath: \PendingWrite.createdAt, ascending: true)
                ]

                let queuedCount = try context.count(for: queuedRequest)
                let failedWrites = try context.fetch(failedRequest)
                let failedRows = failedWrites.map(PendingWriteQueueMapper.summary)

                return HeaderQueueState(
                    pendingCount: queuedCount,
                    failedCount: failedRows.count,
                    failedRows: failedRows
                )
            }

            applyHeaderQueueState(
                pendingCount: snapshot.pendingCount,
                failedCount: snapshot.failedCount,
                failedHeaderRows: snapshot.failedRows
            )
        } catch {
            applyHeaderQueueState(pendingCount: 0, failedCount: 0, failedHeaderRows: [])
            logger.error("Failed to refresh header state: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func runHeaderBackgroundTask<T>(
        _ work: @escaping (NSManagedObjectContext) throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            container.performBackgroundTask { context in
                context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
                do {
                    let result = try work(context)
                    if context.hasChanges {
                        try context.save()
                    }
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
