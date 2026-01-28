import Foundation

// MARK: - Widget Storable Protocol

/// Protocol for all widget data models that can be stored and retrieved
public protocol WidgetStorable: Codable, Identifiable, Equatable {
  var id: String { get }
}

// MARK: - Widget Data Container Protocol

/// Protocol for widget data containers that hold a collection of items
public protocol WidgetDataContainer: Codable, Equatable {
  associatedtype Item: WidgetStorable

  /// The items in this container
  var items: [Item] { get }

  /// Total count of items (may be more than items.count if paginated)
  var totalCount: Int { get }

  /// When this data was last updated
  var lastUpdated: Date { get }

  /// Empty container with no items
  static var empty: Self { get }

  /// Placeholder container for widget previews
  static var placeholder: Self { get }
}
