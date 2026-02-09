import Foundation

// MARK: - WidgetFile Models

/// Lightweight file model for widgets
public struct WidgetFile: WidgetStorable {
  public let id: String
  public let filename: String
  public let path: String?
  public let sizeBytes: Int
  public let pinned: Bool
  public let category: String?
  public let mimeType: String?
  public let recommendedViewer: String?

  public init(
    id: String,
    filename: String,
    path: String? = nil,
    sizeBytes: Int,
    pinned: Bool = false,
    category: String? = nil,
    mimeType: String? = nil,
    recommendedViewer: String? = nil
  ) {
    self.id = id
    self.filename = filename
    self.path = path
    self.sizeBytes = sizeBytes
    self.pinned = pinned
    self.category = category
    self.mimeType = mimeType
    self.recommendedViewer = recommendedViewer
  }
}

/// Data snapshot for file widgets
public struct WidgetFileData: WidgetDataContainer {
  public typealias Item = WidgetFile

  public let files: [WidgetFile]
  public let totalCount: Int
  public let lastUpdated: Date

  public var items: [WidgetFile] { files }

  public init(files: [WidgetFile], totalCount: Int, lastUpdated: Date = Date()) {
    self.files = files
    self.totalCount = totalCount
    self.lastUpdated = lastUpdated
  }

  public static let empty = WidgetFileData(files: [], totalCount: 0)

  public static let placeholder = WidgetFileData(
    files: [
      WidgetFile(id: "1", filename: "Report.pdf", sizeBytes: 1_024_000, pinned: true, category: "Documents"),
      WidgetFile(id: "2", filename: "Notes.txt", sizeBytes: 2048, category: "Text")
    ],
    totalCount: 15
  )
}

// MARK: - IngestionListItem to WidgetFile Conversion

extension WidgetFile {
  /// Creates a WidgetFile from an IngestionListItem
  public init(from item: IngestionListItem) {
    self.id = item.file.id
    self.filename = item.file.filenameOriginal
    self.path = item.file.path
    self.sizeBytes = item.file.sizeBytes
    self.pinned = item.file.pinned ?? false
    self.category = item.file.category
    self.mimeType = item.file.mimeOriginal
    self.recommendedViewer = item.recommendedViewer
  }
}
