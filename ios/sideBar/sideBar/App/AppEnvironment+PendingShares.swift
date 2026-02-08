import Foundation
import sideBarShared

func shouldKeepPendingShareItem(
    _ item: PendingShareItem,
    isOffline: @escaping () -> Bool,
    saveWebsite: @escaping (String) async -> Bool,
    ingestYouTube: @escaping (String) async -> String?,
    resolveFileURL: @escaping (PendingShareItem) -> URL?,
    startUpload: @escaping (URL) -> Bool
) async -> Bool {
    switch item.kind {
    case .website:
        guard let url = item.url else { return false }
        let success = await saveWebsite(url)
        return !success
    case .youtube:
        guard !isOffline() else { return true }
        guard let url = item.url else { return true }
        let error = await ingestYouTube(url)
        return error != nil
    case .file, .image:
        guard !isOffline() else { return true }
        guard let fileURL = resolveFileURL(item) else {
            return true
        }
        let started = startUpload(fileURL)
        return !started
    @unknown default:
        return true
    }
}

extension AppEnvironment {
    public func consumePendingShares() async {
        guard authState == .active else { return }
        guard !connectivityMonitor.isOffline else { return }
        let pending = PendingShareStore.shared.loadAll()
        guard !pending.isEmpty else { return }

        var processedIds: [UUID] = []
        for item in pending {
            let shouldKeep = await shouldKeepPendingShare(item)
            if !shouldKeep {
                processedIds.append(item.id)
            }
        }
        if !processedIds.isEmpty {
            PendingShareStore.shared.remove(ids: processedIds)
        }
    }

    private func shouldKeepPendingShare(_ item: PendingShareItem) async -> Bool {
        await shouldKeepPendingShareItem(
            item,
            isOffline: { [weak self] in
                self?.ingestionViewModel.isOfflineForIngestion() ?? true
            },
            saveWebsite: { [weak self] url in
                guard let self else { return false }
                return await self.websitesViewModel.saveWebsite(url: url)
            },
            ingestYouTube: { [weak self] url in
                guard let self else { return "Environment released." }
                return await self.ingestionViewModel.ingestYouTube(
                    url: url,
                    showQueuedToast: false
                )
            },
            resolveFileURL: { item in
                PendingShareStore.shared.resolveFileURL(for: item)
            },
            startUpload: { [weak self] fileURL in
                guard let self else { return false }
                self.ingestionViewModel.startUpload(url: fileURL)
                return true
            }
        )
    }
}
