import Foundation

public func stripFileExtension(_ name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return name
    }
    let url = URL(fileURLWithPath: trimmed)
    let ext = url.pathExtension
    guard !ext.isEmpty else {
        return trimmed
    }
    let base = url.deletingPathExtension().lastPathComponent
    return base.isEmpty ? trimmed : base
}
