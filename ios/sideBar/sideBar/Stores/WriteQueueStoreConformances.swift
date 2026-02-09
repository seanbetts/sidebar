import Foundation

extension IngestionStore: FilesWriteQueueApplying {}

extension NotesStore: NotesWriteQueueApplying {}

extension TasksStore: TasksWriteQueueApplying {}

extension WebsitesStore: WebsitesWriteQueueApplying {}
