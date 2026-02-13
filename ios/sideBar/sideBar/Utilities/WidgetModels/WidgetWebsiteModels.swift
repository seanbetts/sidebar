import Foundation

// MARK: - WidgetWebsite Models

/// Lightweight website model for widgets
public struct WidgetWebsite: WidgetStorable {
  public let id: String
  public let title: String
  public let url: String
  public let domain: String
  public let faviconUrl: String?
  public let pinned: Bool
  public let pinnedOrder: Int?
  public let archived: Bool

  public init(
    id: String,
    title: String,
    url: String,
    domain: String,
    faviconUrl: String? = nil,
    pinned: Bool = false,
    pinnedOrder: Int? = nil,
    archived: Bool = false
  ) {
    self.id = id
    self.title = title
    self.url = url
    self.domain = domain
    self.faviconUrl = faviconUrl
    self.pinned = pinned
    self.pinnedOrder = pinnedOrder
    self.archived = archived
  }
}

/// Data snapshot for website widgets
public struct WidgetWebsiteData: WidgetDataContainer {
  public typealias Item = WidgetWebsite

  public let websites: [WidgetWebsite]
  public let totalCount: Int
  public let lastUpdated: Date

  public var items: [WidgetWebsite] { websites }

  public init(websites: [WidgetWebsite], totalCount: Int, lastUpdated: Date = Date()) {
    self.websites = websites
    self.totalCount = totalCount
    self.lastUpdated = lastUpdated
  }

  public static let empty = WidgetWebsiteData(websites: [], totalCount: 0)

  public static let placeholder = WidgetWebsiteData(
    websites: [
      WidgetWebsite(id: "1", title: "Apple", url: "https://apple.com", domain: "apple.com"),
      WidgetWebsite(id: "2", title: "GitHub", url: "https://github.com", domain: "github.com")
    ],
    totalCount: 5
  )
}

// MARK: - WebsiteItem to WidgetWebsite Conversion

extension WidgetWebsite {
  /// Creates a WidgetWebsite from a WebsiteItem
  public init(from item: WebsiteItem) {
    self.id = item.id
    self.title = item.title
    self.url = item.url
    self.domain = item.domain
    self.faviconUrl = item.faviconUrl
    self.pinned = item.pinned
    self.pinnedOrder = item.pinnedOrder
    self.archived = item.archived
  }
}
