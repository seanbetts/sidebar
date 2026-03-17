import Foundation
import sideBarShared

// MARK: - WebsiteItem to WidgetWebsite Conversion

extension WidgetWebsite {
  /// Creates a WidgetWebsite from a WebsiteItem
  public init(from item: WebsiteItem) {
    self.init(
      id: item.id,
      title: item.title,
      url: item.url,
      domain: item.domain,
      faviconUrl: item.faviconUrl,
      faviconR2Key: item.faviconR2Key,
      pinned: item.pinned,
      pinnedOrder: item.pinnedOrder,
      archived: item.archived
    )
  }
}
