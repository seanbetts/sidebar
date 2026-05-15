import Foundation
import sideBarShared

public enum OnboardingDiscoveryFeature: String, Identifiable, Equatable, CaseIterable {
    case notes
    case tasks
    case websites
    case files
    case skills

    public static let allCases: [OnboardingDiscoveryFeature] = [
        .notes,
        .tasks,
        .websites,
        .files,
        .skills
    ]

    public var id: String { rawValue }

    public var title: String {
        switch self {
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
        case .notes:
            "Capture ideas, keep scratch work close, and organize them later."
        case .tasks:
            "Track projects, due dates, and follow-up without leaving sideBar."
        case .websites:
            "Save articles and links so the assistant can reference them later."
        case .files:
            "Upload PDFs and documents, then search or ask questions about them."
        case .skills:
            "Extend what sideBar can do with additional skill from the skills store"
        }
    }

    public var appIcon: AppIcon {
        switch self {
        case .notes:
            AppIcon.Domain.notes
        case .tasks:
            AppIcon.Domain.tasks
        case .websites:
            AppIcon.Domain.websites
        case .files:
            AppIcon.Domain.files
        case .skills:
            AppIcon.Domain.skillsStore
        }
    }

    public var kickoffPrompt: String {
        switch self {
        case .notes:
            "Help me get started with notes in sideBar. "
                + "Write me a short guided intro as a note to demonstrate how notes work, "
                + "showing off and explaining all the features."
        case .tasks:
            "Help me get started with Tasks in sideBar. Give me a short guided intro and create a simple task to show off all the features."
        case .websites:
            "Help me get started with Websites in sideBar. "
                + "Give me a short guided intro and save "
                + "https://docs.trysidebar.ai/manual/introduction "
                + "to show off all the features."
        case .files:
            "Help me get started with Files in sideBar. Give me a short guided intro that covers all of the features."
        case .skills:
            "Help me get started with Skills in sideBar. Give me a short guided intro and a summary of some of the best skills."
        }
    }
}
