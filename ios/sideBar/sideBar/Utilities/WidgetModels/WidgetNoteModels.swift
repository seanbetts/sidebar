import Foundation
import sideBarShared

// MARK: - FileNode to WidgetNote Conversion

extension WidgetNote {
  /// Creates a WidgetNote from a FileNode
  public init(from node: FileNode) {
    self.init(
      id: node.path,
      name: node.name,
      contentPreview: nil,
      path: node.path,
      modifiedAt: node.modified.map { Date(timeIntervalSince1970: $0) },
      pinned: node.pinned ?? false,
      pinnedOrder: node.pinnedOrder
    )
  }
}
