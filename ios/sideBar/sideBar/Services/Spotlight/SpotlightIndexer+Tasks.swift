import Foundation
import CoreSpotlight
import UniformTypeIdentifiers
import os

/// Lightweight model for task indexing.
public struct SpotlightTask {
  public let id: String
  public let title: String
  public let notes: String?
  public let status: String
  public let deadline: String?

  public init(
    id: String,
    title: String,
    notes: String?,
    status: String,
    deadline: String?
  ) {
    self.id = id
    self.title = title
    self.notes = notes
    self.status = status
    self.deadline = deadline
  }
}

extension SpotlightIndexer {
  static let tasksDomain = "com.sidebar.tasks"

  public func indexTask(_ task: SpotlightTask) async {
    let item = makeTaskSearchableItem(task)
    do {
      try await index.indexSearchableItems([item])
      logger.debug("Indexed task: \(task.id, privacy: .public)")
    } catch {
      logger.error("Failed to index task \(task.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
  }

  public func indexTasks(_ tasks: [SpotlightTask]) async {
    guard !tasks.isEmpty else { return }

    for start in stride(from: 0, to: tasks.count, by: batchSize) {
      let batch = Array(tasks[start..<Swift.min(start + batchSize, tasks.count)])
      let items = batch.map { makeTaskSearchableItem($0) }
      do {
        try await index.indexSearchableItems(items)
        logger.debug("Indexed \(items.count) tasks")
      } catch {
        logger.error("Failed to index tasks batch: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  public func removeTask(id: String) async {
    let identifier = taskIdentifier(for: id)
    do {
      try await index.deleteSearchableItems(withIdentifiers: [identifier])
      logger.debug("Removed task from index: \(id, privacy: .public)")
    } catch {
      logger.error("Failed to remove task \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
  }

  public func clearTasksIndex() async {
    do {
      try await index.deleteSearchableItems(withDomainIdentifiers: [Self.tasksDomain])
      logger.info("Cleared tasks index")
    } catch {
      logger.error("Failed to clear tasks index: \(error.localizedDescription, privacy: .public)")
    }
  }

  private func taskIdentifier(for id: String) -> String {
    "task:\(id)"
  }

  private func makeTaskSearchableItem(_ task: SpotlightTask) -> CSSearchableItem {
    let attributes = CSSearchableItemAttributeSet(contentType: .text)

    attributes.title = task.title
    attributes.contentDescription = task.deadline?.isEmpty == false ? "Due \(task.deadline!)" : "Task"

    let searchableParts = [
      task.title,
      task.status,
      task.deadline ?? ""
    ].filter { !$0.isEmpty }
    attributes.textContent = searchableParts.joined(separator: " ")

    var keywords = task.title
      .replacingOccurrences(of: "-", with: " ")
      .replacingOccurrences(of: "_", with: " ")
      .split(separator: " ")
      .map(String.init)
    keywords.append(task.status)
    if let deadline = task.deadline, !deadline.isEmpty {
      keywords.append(deadline)
    }
    attributes.keywords = keywords

    let identifier = taskIdentifier(for: task.id)
    return CSSearchableItem(
      uniqueIdentifier: identifier,
      domainIdentifier: Self.tasksDomain,
      attributeSet: attributes
    )
  }
}

extension NoOpSpotlightIndexer {
  public func indexTask(_ task: SpotlightTask) async { _ = task }
  public func indexTasks(_ tasks: [SpotlightTask]) async { _ = tasks }
  public func removeTask(id: String) async { _ = id }
  public func clearTasksIndex() async {}
}
