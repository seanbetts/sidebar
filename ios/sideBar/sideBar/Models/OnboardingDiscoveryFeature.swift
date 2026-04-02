import Foundation

public enum OnboardingDiscoveryFeature: String, CaseIterable, Identifiable, Equatable {
    case chat
    case notes
    case tasks
    case websites
    case files
    case skills

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .chat:
            "Chat"
        case .notes:
            "Notes"
        case .tasks:
            "Tasks"
        case .websites:
            "Websites"
        case .files:
            "Files"
        case .skills:
            "Skills"
        }
    }

    public var summary: String {
        switch self {
        case .chat:
            "Ask questions, take action, and use skills across your workspace."
        case .notes:
            "Capture ideas, keep scratch work close, and organize them later."
        case .tasks:
            "Track projects, due dates, and follow-up without leaving sideBar."
        case .websites:
            "Save articles and links so the assistant can reference them later."
        case .files:
            "Upload PDFs and documents, then search or ask questions about them."
        case .skills:
            "Extend what the assistant can do with built-in and store skills."
        }
    }

    public var systemImage: String {
        switch self {
        case .chat:
            "bubble"
        case .notes:
            "text.document"
        case .tasks:
            "checkmark.square"
        case .websites:
            "globe"
        case .files:
            "folder"
        case .skills:
            "command.circle"
        }
    }

    public var kickoffPrompt: String {
        switch self {
        case .chat:
            "Help me get started with Chat in sideBar. Give me a short guided intro and one simple first win."
        case .notes:
            "Help me get started with Notes in sideBar. Give me a short guided intro and one simple first win."
        case .tasks:
            "Help me get started with Tasks in sideBar. Give me a short guided intro and one simple first win."
        case .websites:
            "Help me get started with Websites in sideBar. Give me a short guided intro and one simple first win."
        case .files:
            "Help me get started with Files in sideBar. Give me a short guided intro and one simple first win."
        case .skills:
            "Help me get started with Skills in sideBar. Give me a short guided intro and one simple first win."
        }
    }
}
