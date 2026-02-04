import Foundation
import sideBarShared

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
        switch item.kind {
        case .website:
            return await handlePendingWebsite(item)
        case .youtube:
            return await handlePendingYouTube(item)
        case .file, .image:
            return handlePendingFile(item)
        @unknown default:
            return true
        }
    }

    private func handlePendingWebsite(_ item: PendingShareItem) async -> Bool {
        guard let url = item.url else { return false }
        let success = await websitesViewModel.saveWebsite(url: url)
        return !success
    }

    private func handlePendingYouTube(_ item: PendingShareItem) async -> Bool {
        guard let url = item.url else { return true }
        let error = await ingestionViewModel.ingestYouTube(url: url, showQueuedToast: false)
        return error != nil
    }

    private func handlePendingFile(_ item: PendingShareItem) -> Bool {
        guard let fileURL = PendingShareStore.shared.resolveFileURL(for: item) else {
            return true
        }
        ingestionViewModel.startUpload(url: fileURL)
        return false
    }
}
