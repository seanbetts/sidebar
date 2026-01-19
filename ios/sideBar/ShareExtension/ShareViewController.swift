import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private var environment: ShareExtensionEnvironment?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        do {
            environment = try ShareExtensionEnvironment()
        } catch {
            showError(error.localizedDescription)
            return
        }
        extractSharedURL()
    }

    private func extractSharedURL() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            showError(ShareExtensionError.invalidSharePayload.localizedDescription)
            return
        }

        let itemProviders = extensionItems.flatMap { $0.attachments ?? [] }
        let supportedTypes: [UTType] = [.url, .plainText, .text, .html]
        Task { [weak self] in
            guard let self else { return }
            for itemProvider in itemProviders {
                let candidateIdentifiers = itemProvider.registeredTypeIdentifiers.compactMap { identifier -> String? in
                    guard let type = UTType(identifier) else { return nil }
                    if type.conforms(to: .url)
                        || type.conforms(to: .text)
                        || type.conforms(to: .plainText)
                        || type.conforms(to: .html) {
                        return identifier
                    }
                    return nil
                }
                let identifiersToTry = candidateIdentifiers.isEmpty
                    ? supportedTypes.map(\.identifier)
                    : candidateIdentifiers
                for identifier in identifiersToTry where itemProvider.hasItemConformingToTypeIdentifier(identifier) {
                    if let url = await self.loadURL(from: itemProvider, typeIdentifier: identifier) {
                        await MainActor.run { [weak self] in
                            self?.saveURL(url)
                        }
                        return
                    }
                }
            }
            await MainActor.run { [weak self] in
                self?.showError("No URL found in shared content.")
            }
        }
    }

    private func saveURL(_ url: URL) {
        guard let environment else {
            showError(ShareExtensionError.notAuthenticated.localizedDescription)
            return
        }
        setContentView(ShareLoadingView(message: "Saving website..."))
        Task { @MainActor in
            do {
                _ = try await environment.websitesAPI.quickSave(url: url.absoluteString, title: nil)
                ExtensionEventStore.shared.recordWebsiteSaved(url: url.absoluteString)
                showSuccess()
            } catch {
                showError(error.localizedDescription)
            }
        }
    }

    private func showError(_ message: String) {
        setContentView(ShareErrorView(message: message))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func showSuccess() {
        setContentView(ShareSuccessView(message: "Website saved"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func setContentView(_ content: UIView) {
        view.subviews.forEach { $0.removeFromSuperview() }
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: view.topAnchor),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func urlFromTextPayload(_ item: Any?) -> URL? {
        if let url = item as? URL {
            if url.isFileURL, let fileURL = extractURLFromFile(url) {
                return fileURL
            }
            return url
        }
        if let attributed = item as? NSAttributedString {
            if let url = extractFirstLink(from: attributed) {
                return url
            }
            return extractFirstURL(from: attributed.string)
        }
        if let string = item as? String {
            return extractFirstURL(from: string)
        }
        if let string = item as? NSString {
            return extractFirstURL(from: string as String)
        }
        if let data = item as? Data,
           let string = String(data: data, encoding: .utf8) {
            return extractFirstURL(from: string)
        }
        return nil
    }

    private func extractFirstLink(from attributed: NSAttributedString) -> URL? {
        var found: URL?
        let range = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttribute(.link, in: range, options: []) { value, _, stop in
            if let url = value as? URL {
                found = url
                stop.pointee = true
            } else if let string = value as? String, let url = URL(string: string) {
                found = url
                stop.pointee = true
            }
        }
        return found
    }

    private func extractFirstURL(from text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = detector.firstMatch(in: text, options: [], range: range),
              let url = match.url else {
            return nil
        }
        return url
    }

    private func extractURLFromFile(_ url: URL) -> URL? {
        guard let string = readTextFile(url) else { return nil }
        return extractFirstURL(from: string)
    }

    private func readTextFile(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let maxBytes = 64 * 1024
        let limitedData = data.count > maxBytes ? data.prefix(maxBytes) : data
        return String(data: limitedData, encoding: .utf8)
    }

    private func loadURL(from itemProvider: NSItemProvider, typeIdentifier: String) async -> URL? {
        if let item = await loadItem(from: itemProvider, typeIdentifier: typeIdentifier),
           let url = urlFromTextPayload(item) {
            return url
        }
        if let data = await loadData(from: itemProvider, typeIdentifier: typeIdentifier),
           let url = urlFromTextPayload(data) {
            return url
        }
        return nil
    }

    private func loadItem(from itemProvider: NSItemProvider, typeIdentifier: String) async -> Any? {
        await withCheckedContinuation { continuation in
            itemProvider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                continuation.resume(returning: item)
            }
        }
    }

    private func loadData(from itemProvider: NSItemProvider, typeIdentifier: String) async -> Data? {
        await withCheckedContinuation { continuation in
            itemProvider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}
