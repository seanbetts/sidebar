import Foundation
import sideBarShared

func shouldKeepPendingShareItem(
    _ item: PendingShareItem,
    saveWebsite: @escaping (String) async -> Bool,
    ingestYouTube: @escaping (String) async -> String?,
    resolveFileURL: @escaping (PendingShareItem) -> URL?,
    startUpload: @escaping (URL) -> Void
) async -> Bool {
    switch item.kind {
    case .website:
        guard let url = item.url else { return false }
        let success = await saveWebsite(url)
        return !success
    case .youtube:
        guard let url = item.url else { return true }
        let error = await ingestYouTube(url)
        return error != nil
    case .file, .image:
        guard let fileURL = resolveFileURL(item) else {
            return true
        }
        startUpload(fileURL)
        return false
    @unknown default:
        return true
    }
}

extension AppEnvironment {
    public func consumePendingShares() async {
        guard authState == .active else { return }
        guard !connectivityMonitor.isOffline else { return }
        let pending = PendingShareStore.shared.consumeAll()
        guard !pending.isEmpty else { return }

        let remaining = await filterPendingShares(pending)
        PendingShareStore.shared.replaceAll(remaining)
    }

    private func filterPendingShares(_ items: [PendingShareItem]) async -> [PendingShareItem] {
        var remaining: [PendingShareItem] = []
        for item in items where await shouldKeepPendingShare(item) {
            remaining.append(item)
        }
        return remaining
    }

    private func shouldKeepPendingShare(_ item: PendingShareItem) async -> Bool {
        await shouldKeepPendingShareItem(
            item,
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
                self?.ingestionViewModel.startUpload(url: fileURL)
            }
        )
    }
}
