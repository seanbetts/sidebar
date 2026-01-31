import Foundation
import sideBarShared

extension AppEnvironment {
    public func consumePendingShares() async {
        guard isAuthenticated else { return }
        guard !connectivityMonitor.isOffline else { return }
        let pending = PendingShareStore.shared.loadAll()
        guard !pending.isEmpty else { return }

        var remaining: [PendingShareItem] = []

        for item in pending {
            switch item.kind {
            case .website:
                guard let url = item.url else {
                    continue
                }
                let success = await websitesViewModel.saveWebsite(url: url)
                if !success {
                    remaining.append(item)
                }
            case .file, .image:
                guard let fileURL = PendingShareStore.shared.resolveFileURL(for: item) else {
                    remaining.append(item)
                    continue
                }
                ingestionViewModel.startUpload(url: fileURL)
            @unknown default:
                remaining.append(item)
            }
        }

        PendingShareStore.shared.replaceAll(remaining)
    }
}
