import Foundation
import sideBarShared

#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

enum IngestionProgressActivityStatus: String, Equatable {
    case uploading
    case processing
    case completed
    case failed
    case canceled
}

struct IngestionProgressActivitySnapshot: Equatable {
    let fileID: String
    let displayName: String
    let status: IngestionProgressActivityStatus
    let stage: String
    let progress: Double?
    let statusText: String
    let detailText: String?

    var isTerminal: Bool {
        switch status {
        case .completed, .failed, .canceled:
            return true
        case .uploading, .processing:
            return false
        }
    }

    var attributes: IngestionProgressActivityAttributes {
        IngestionProgressActivityAttributes(
            fileID: fileID,
            displayName: displayName
        )
    }

    var contentState: IngestionProgressActivityAttributes.ContentState {
        IngestionProgressActivityAttributes.ContentState(
            status: status.rawValue,
            stage: stage,
            progress: progress,
            statusText: statusText,
            detailText: detailText
        )
    }
}

protocol IngestionProgressActivityClient {
    func start(snapshot: IngestionProgressActivitySnapshot) async -> String
    func update(activityID: String, snapshot: IngestionProgressActivitySnapshot) async
    func end(activityID: String, finalSnapshot: IngestionProgressActivitySnapshot?) async
}

@MainActor
final class IngestionProgressActivityCoordinator {
    private let client: any IngestionProgressActivityClient
    private var activityIDsByFileID: [String: String] = [:]
    private var snapshotsByFileID: [String: IngestionProgressActivitySnapshot] = [:]

    init() {
        self.client = LiveIngestionProgressActivityClient()
    }

    init(client: any IngestionProgressActivityClient) {
        self.client = client
    }

    func reconcile(items: [IngestionListItem]) async {
        var seenFileIDs = Set<String>()

        for item in items {
            guard let snapshot = snapshot(for: item) else { continue }
            let fileID = snapshot.fileID
            seenFileIDs.insert(fileID)

            if snapshot.isTerminal {
                guard let activityID = activityIDsByFileID[fileID] else { continue }
                await client.end(activityID: activityID, finalSnapshot: snapshot)
                activityIDsByFileID.removeValue(forKey: fileID)
                snapshotsByFileID.removeValue(forKey: fileID)
                continue
            }

            if let activityID = activityIDsByFileID[fileID] {
                guard snapshotsByFileID[fileID] != snapshot else { continue }
                await client.update(activityID: activityID, snapshot: snapshot)
                snapshotsByFileID[fileID] = snapshot
                continue
            }

            let activityID = await client.start(snapshot: snapshot)
            activityIDsByFileID[fileID] = activityID
            snapshotsByFileID[fileID] = snapshot
        }

        for fileID in activityIDsByFileID.keys.filter({ !seenFileIDs.contains($0) }) {
            guard let activityID = activityIDsByFileID[fileID] else { continue }
            await client.end(activityID: activityID, finalSnapshot: nil)
            activityIDsByFileID.removeValue(forKey: fileID)
            snapshotsByFileID.removeValue(forKey: fileID)
        }
    }

    private func snapshot(for item: IngestionListItem) -> IngestionProgressActivitySnapshot? {
        guard IdentifierValidation.isServerFileID(item.file.id) else {
            return nil
        }

        let statusValue = [IngestionListItem].normalizedStatus(item.job.status ?? "")
        guard !statusValue.isEmpty else {
            return nil
        }

        let stageValue = [IngestionListItem].normalizedStatus(item.job.stage ?? "")
        let status = mappedStatus(for: statusValue)
        let progress = item.job.progress.map { min(max($0, 0), 1) }
        let displayName = displayName(for: item.file.filenameOriginal)

        return IngestionProgressActivitySnapshot(
            fileID: item.file.id,
            displayName: displayName,
            status: status,
            stage: stageValue.isEmpty ? statusValue : stageValue,
            progress: progress,
            statusText: ingestionStatusLabel(for: item.job) ?? fallbackStatusText(for: status),
            detailText: ingestionStatusDetail(
                for: item.job,
                statusLabel: ingestionStatusLabel(for: item.job)
            )
        )
    }

    private func mappedStatus(for value: String) -> IngestionProgressActivityStatus {
        switch value {
        case "uploading":
            return .uploading
        case "ready":
            return .completed
        case "failed":
            return .failed
        case "canceled":
            return .canceled
        default:
            return .processing
        }
    }

    private func fallbackStatusText(for status: IngestionProgressActivityStatus) -> String {
        switch status {
        case .uploading:
            return "Uploading..."
        case .processing:
            return "Processing"
        case .completed:
            return "Ready"
        case .failed:
            return "Failed"
        case .canceled:
            return "Canceled"
        }
    }

    private func displayName(for filename: String) -> String {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "File"
        }
        let extensionValue = URL(fileURLWithPath: trimmed).pathExtension
        guard !extensionValue.isEmpty else {
            return trimmed
        }
        return URL(fileURLWithPath: trimmed).deletingPathExtension().lastPathComponent
    }
}

struct LiveIngestionProgressActivityClient: IngestionProgressActivityClient {
    func start(snapshot: IngestionProgressActivitySnapshot) async -> String {
        #if canImport(ActivityKit) && os(iOS)
        guard #available(iOS 16.2, *), ActivityAuthorizationInfo().areActivitiesEnabled else {
            return snapshot.fileID
        }

        if let existing = activity(forFileID: snapshot.fileID) {
            await update(activityID: existing.id, snapshot: snapshot)
            return existing.id
        }

        do {
            let activity = try Activity.request(
                attributes: snapshot.attributes,
                content: ActivityContent(state: snapshot.contentState, staleDate: nil),
                pushType: nil
            )
            return activity.id
        } catch {
            return snapshot.fileID
        }
        #else
        return snapshot.fileID
        #endif
    }

    func update(activityID: String, snapshot: IngestionProgressActivitySnapshot) async {
        #if canImport(ActivityKit) && os(iOS)
        guard #available(iOS 16.2, *),
              let activity = activity(activityID: activityID, fileID: snapshot.fileID) else {
            return
        }

        await activity.update(
            ActivityContent(state: snapshot.contentState, staleDate: nil)
        )
        #else
        _ = activityID
        _ = snapshot
        #endif
    }

    func end(activityID: String, finalSnapshot: IngestionProgressActivitySnapshot?) async {
        #if canImport(ActivityKit) && os(iOS)
        guard #available(iOS 16.2, *) else {
            return
        }

        let fileID = finalSnapshot?.fileID
        guard let activity = activity(activityID: activityID, fileID: fileID) else {
            return
        }

        let content = finalSnapshot.map {
            ActivityContent(state: $0.contentState, staleDate: nil)
        }
        await activity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(30)))
        #else
        _ = activityID
        _ = finalSnapshot
        #endif
    }

    #if canImport(ActivityKit) && os(iOS)
    @available(iOS 16.2, *)
    private func activity(
        activityID: String,
        fileID: String?
    ) -> Activity<IngestionProgressActivityAttributes>? {
        if let existingByID = Activity<IngestionProgressActivityAttributes>.activities.first(where: {
            $0.id == activityID
        }) {
            return existingByID
        }

        guard let fileID else {
            return nil
        }
        return activity(forFileID: fileID)
    }

    @available(iOS 16.2, *)
    private func activity(forFileID fileID: String) -> Activity<IngestionProgressActivityAttributes>? {
        Activity<IngestionProgressActivityAttributes>.activities.first(where: {
            $0.attributes.fileID == fileID
        })
    }
    #endif
}
