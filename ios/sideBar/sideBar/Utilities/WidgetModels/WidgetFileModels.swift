import Foundation
import sideBarShared

// MARK: - IngestionListItem to WidgetFile Conversion

extension WidgetFile {
  /// Creates a WidgetFile from an IngestionListItem
  public init(from item: IngestionListItem) {
    self.init(
      id: item.file.id,
      filename: item.file.filenameOriginal,
      path: item.file.path,
      sizeBytes: item.file.sizeBytes,
      pinned: item.file.pinned ?? false,
      category: item.file.category,
      mimeType: item.file.mimeOriginal,
      recommendedViewer: item.recommendedViewer
    )
  }
}
