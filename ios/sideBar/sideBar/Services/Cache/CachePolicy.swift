import Foundation

public enum CachePolicy {
    public static let conversationsList: TimeInterval = 30 * 60
    public static let conversationDetail: TimeInterval = 2 * 60 * 60
    public static let notesTree: TimeInterval = 30 * 60
    public static let noteContent: TimeInterval = 2 * 60 * 60
    public static let websitesList: TimeInterval = 30 * 60
    public static let websiteDetail: TimeInterval = 2 * 60 * 60
    public static let memoriesList: TimeInterval = 30 * 60
    public static let ingestionList: TimeInterval = 10 * 60
    public static let scratchpad: TimeInterval = 7 * 24 * 60 * 60
    public static let filesTree: TimeInterval = 30 * 60
    public static let fileContent: TimeInterval = 2 * 60 * 60
    public static let userSettings: TimeInterval = 30 * 60
    public static let skillsList: TimeInterval = 30 * 60
}
