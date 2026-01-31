import Foundation
import CoreSpotlight
import UniformTypeIdentifiers
import os

// MARK: - SpotlightIndexing Protocol

/// Protocol for Spotlight indexing operations, enabling testability.
public protocol SpotlightIndexing: AnyObject {
  func indexNote(_ note: SpotlightNote) async
  func indexNotes(_ notes: [SpotlightNote]) async
  func indexFile(_ file: SpotlightFile) async
  func indexFiles(_ files: [SpotlightFile]) async
  func indexWebsite(_ website: SpotlightWebsite) async
  func indexWebsites(_ websites: [SpotlightWebsite]) async
  func removeNote(path: String) async
  func removeFile(id: String) async
  func removeWebsite(id: String) async
  func clearNotesIndex() async
  func clearFilesIndex() async
  func clearWebsitesIndex() async
  func clearAllIndexes() async
}

// MARK: - Spotlight Models

/// Lightweight model for note indexing.
public struct SpotlightNote {
  public let path: String
  public let name: String
  public let content: String?
  public let modified: Date?

  public init(path: String, name: String, content: String?, modified: Date?) {
    self.path = path
    self.name = name
    self.content = content
    self.modified = modified
  }
}

/// Lightweight model for file indexing.
public struct SpotlightFile {
  public let id: String
  public let filename: String
  public let category: String?
  public let mimeType: String
  public let sizeBytes: Int
  public let createdAt: Date?

  public init(
    id: String,
    filename: String,
    category: String?,
    mimeType: String,
    sizeBytes: Int,
    createdAt: Date?
  ) {
    self.id = id
    self.filename = filename
    self.category = category
    self.mimeType = mimeType
    self.sizeBytes = sizeBytes
    self.createdAt = createdAt
  }
}

/// Lightweight model for website indexing.
public struct SpotlightWebsite {
  public let id: String
  public let title: String
  public let url: String
  public let domain: String
  public let savedAt: Date?

  public init(
    id: String,
    title: String,
    url: String,
    domain: String,
    savedAt: Date?
  ) {
    self.id = id
    self.title = title
    self.url = url
    self.domain = domain
    self.savedAt = savedAt
  }
}

// MARK: - SpotlightIndexer

/// CoreSpotlight indexer for notes and files.
///
/// Indexes notes and files so they appear in iOS Spotlight search.
/// Tapping a result opens the app via deep link.
public final class SpotlightIndexer: SpotlightIndexing {
  private let index: CSSearchableIndex
  private let logger = Logger(subsystem: "sideBar", category: "Spotlight")

  static let notesDomain = "com.sidebar.notes"
  static let filesDomain = "com.sidebar.files"
  static let websitesDomain = "com.sidebar.websites"
  private let batchSize = 100
  private let contentPreviewLength = 200

  public init(index: CSSearchableIndex = .default()) {
    self.index = index
  }

  // MARK: - Note Indexing

  public func indexNote(_ note: SpotlightNote) async {
    let item = makeNoteSearchableItem(note)
    do {
      try await index.indexSearchableItems([item])
      logger.debug("Indexed note: \(note.path, privacy: .public)")
    } catch {
      logger.error("Failed to index note \(note.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
  }

  public func indexNotes(_ notes: [SpotlightNote]) async {
    guard !notes.isEmpty else { return }

    for batch in notes.chunked(into: batchSize) {
      let items = batch.map { makeNoteSearchableItem($0) }
      do {
        try await index.indexSearchableItems(items)
        logger.debug("Indexed \(items.count) notes")
      } catch {
        logger.error("Failed to index notes batch: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  public func removeNote(path: String) async {
    let identifier = noteIdentifier(for: path)
    do {
      try await index.deleteSearchableItems(withIdentifiers: [identifier])
      logger.debug("Removed note from index: \(path, privacy: .public)")
    } catch {
      logger.error("Failed to remove note \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
  }

  public func clearNotesIndex() async {
    do {
      try await index.deleteSearchableItems(withDomainIdentifiers: [Self.notesDomain])
      logger.info("Cleared notes index")
    } catch {
      logger.error("Failed to clear notes index: \(error.localizedDescription, privacy: .public)")
    }
  }

  // MARK: - File Indexing

  public func indexFile(_ file: SpotlightFile) async {
    let item = makeFileSearchableItem(file)
    do {
      try await index.indexSearchableItems([item])
      logger.debug("Indexed file: \(file.id, privacy: .public)")
    } catch {
      logger.error("Failed to index file \(file.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
  }

  public func indexFiles(_ files: [SpotlightFile]) async {
    guard !files.isEmpty else { return }

    for batch in files.chunked(into: batchSize) {
      let items = batch.map { makeFileSearchableItem($0) }
      do {
        try await index.indexSearchableItems(items)
        logger.debug("Indexed \(items.count) files")
      } catch {
        logger.error("Failed to index files batch: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  public func removeFile(id: String) async {
    let identifier = fileIdentifier(for: id)
    do {
      try await index.deleteSearchableItems(withIdentifiers: [identifier])
      logger.debug("Removed file from index: \(id, privacy: .public)")
    } catch {
      logger.error("Failed to remove file \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
  }

  public func clearFilesIndex() async {
    do {
      try await index.deleteSearchableItems(withDomainIdentifiers: [Self.filesDomain])
      logger.info("Cleared files index")
    } catch {
      logger.error("Failed to clear files index: \(error.localizedDescription, privacy: .public)")
    }
  }

  // MARK: - Website Indexing

  public func indexWebsite(_ website: SpotlightWebsite) async {
    let item = makeWebsiteSearchableItem(website)
    do {
      try await index.indexSearchableItems([item])
      logger.debug("Indexed website: \(website.id, privacy: .public)")
    } catch {
      logger.error("Failed to index website \(website.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
  }

  public func indexWebsites(_ websites: [SpotlightWebsite]) async {
    guard !websites.isEmpty else { return }

    for batch in websites.chunked(into: batchSize) {
      let items = batch.map { makeWebsiteSearchableItem($0) }
      do {
        try await index.indexSearchableItems(items)
        logger.debug("Indexed \(items.count) websites")
      } catch {
        logger.error("Failed to index websites batch: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  public func removeWebsite(id: String) async {
    let identifier = websiteIdentifier(for: id)
    do {
      try await index.deleteSearchableItems(withIdentifiers: [identifier])
      logger.debug("Removed website from index: \(id, privacy: .public)")
    } catch {
      logger.error("Failed to remove website \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
  }

  public func clearWebsitesIndex() async {
    do {
      try await index.deleteSearchableItems(withDomainIdentifiers: [Self.websitesDomain])
      logger.info("Cleared websites index")
    } catch {
      logger.error("Failed to clear websites index: \(error.localizedDescription, privacy: .public)")
    }
  }

  // MARK: - Clear All

  public func clearAllIndexes() async {
    await clearNotesIndex()
    await clearFilesIndex()
    await clearWebsitesIndex()
  }

  // MARK: - Private Helpers

  private func noteIdentifier(for path: String) -> String {
    "note:\(path)"
  }

  private func fileIdentifier(for id: String) -> String {
    "file:\(id)"
  }

  private func websiteIdentifier(for id: String) -> String {
    "website:\(id)"
  }

  private func makeNoteSearchableItem(_ note: SpotlightNote) -> CSSearchableItem {
    let attributes = CSSearchableItemAttributeSet(contentType: .text)

    // Title: note name without .md extension
    let displayName = note.name.hasSuffix(".md")
      ? String(note.name.dropLast(3))
      : note.name
    attributes.title = displayName

    // Content preview (first N chars) for display, if content available
    if let content = note.content {
      let preview = String(content.prefix(contentPreviewLength))
      attributes.contentDescription = preview
      attributes.textContent = content
    }

    // Modification date
    attributes.contentModificationDate = note.modified

    // Keywords: path components for folder-based search
    let pathComponents = note.path.split(separator: "/").map(String.init)
    attributes.keywords = pathComponents

    let identifier = noteIdentifier(for: note.path)
    return CSSearchableItem(
      uniqueIdentifier: identifier,
      domainIdentifier: Self.notesDomain,
      attributeSet: attributes
    )
  }

  private func makeFileSearchableItem(_ file: SpotlightFile) -> CSSearchableItem {
    let contentType = UTType(mimeType: file.mimeType) ?? .data
    let attributes = CSSearchableItemAttributeSet(contentType: contentType)

    // Title: filename
    attributes.title = file.filename

    // Content description: category + "file"
    if let category = file.category {
      attributes.contentDescription = "\(category.capitalized) file"
    } else {
      attributes.contentDescription = "File"
    }

    // Searchable text - filename so Spotlight can find it
    attributes.textContent = file.filename

    // Keywords: filename parts and category for search
    var keywords = file.filename
      .replacingOccurrences(of: ".", with: " ")
      .replacingOccurrences(of: "_", with: " ")
      .replacingOccurrences(of: "-", with: " ")
      .split(separator: " ")
      .map(String.init)
    if let category = file.category {
      keywords.append(category)
    }
    attributes.keywords = keywords

    // File metadata
    attributes.fileSize = NSNumber(value: file.sizeBytes)
    attributes.contentCreationDate = file.createdAt
    attributes.contentType = contentType.identifier

    let identifier = fileIdentifier(for: file.id)
    return CSSearchableItem(
      uniqueIdentifier: identifier,
      domainIdentifier: Self.filesDomain,
      attributeSet: attributes
    )
  }

  private func makeWebsiteSearchableItem(_ website: SpotlightWebsite) -> CSSearchableItem {
    let attributes = CSSearchableItemAttributeSet(contentType: .url)

    // Title
    attributes.title = website.title

    // URL and domain for display
    attributes.contentDescription = website.domain
    attributes.url = URL(string: website.url)

    // Searchable text - title, domain, and URL
    attributes.textContent = "\(website.title) \(website.domain) \(website.url)"

    // Keywords: title words and domain
    var keywords = website.title
      .replacingOccurrences(of: "-", with: " ")
      .replacingOccurrences(of: "_", with: " ")
      .split(separator: " ")
      .map(String.init)
    keywords.append(website.domain)
    attributes.keywords = keywords

    // Saved date
    attributes.contentCreationDate = website.savedAt

    let identifier = websiteIdentifier(for: website.id)
    return CSSearchableItem(
      uniqueIdentifier: identifier,
      domainIdentifier: Self.websitesDomain,
      attributeSet: attributes
    )
  }
}

// MARK: - Array Extension

private extension Array {
  func chunked(into size: Int) -> [[Element]] {
    stride(from: 0, to: count, by: size).map {
      Array(self[$0..<Swift.min($0 + size, count)])
    }
  }
}

// MARK: - Identifier Parsing

extension SpotlightIndexer {
  /// Parses a Spotlight identifier into a deep link URL.
  /// - Parameter identifier: The CSSearchableItemActivityIdentifier (e.g., "note:path/to/note.md" or "file:uuid")
  /// - Returns: A sidebar:// URL if the identifier is valid, nil otherwise.
  public static func deepLinkURL(from identifier: String) -> URL? {
    if identifier.hasPrefix("note:") {
      let path = String(identifier.dropFirst(5))
      guard !path.isEmpty else { return nil }
      let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
      return URL(string: "sidebar://notes/\(encoded)")
    } else if identifier.hasPrefix("file:") {
      let id = String(identifier.dropFirst(5))
      guard !id.isEmpty else { return nil }
      return URL(string: "sidebar://files/\(id)")
    } else if identifier.hasPrefix("website:") {
      let id = String(identifier.dropFirst(8))
      guard !id.isEmpty else { return nil }
      return URL(string: "sidebar://websites/\(id)")
    }
    return nil
  }
}
