import AppIntents
import WidgetKit
import sideBarShared

// MARK: - Widget Configuration

enum FileWidgetScope: String, AppEnum {
    case all
    case category

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "File Scope")
    static var caseDisplayRepresentations: [FileWidgetScope: DisplayRepresentation] = [
        .all: DisplayRepresentation(title: "All pinned files"),
        .category: DisplayRepresentation(title: "Category")
    ]
}

enum FileWidgetCategory: String, AppEnum, CaseIterable {
    case documents
    case images
    case audio
    case video
    case spreadsheets
    case reports
    case presentations
    case other

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "File Category")
    static var caseDisplayRepresentations: [FileWidgetCategory: DisplayRepresentation] = [
        .documents: DisplayRepresentation(title: "Documents"),
        .images: DisplayRepresentation(title: "Images"),
        .audio: DisplayRepresentation(title: "Audio"),
        .video: DisplayRepresentation(title: "Video"),
        .spreadsheets: DisplayRepresentation(title: "Spreadsheets"),
        .reports: DisplayRepresentation(title: "Reports"),
        .presentations: DisplayRepresentation(title: "Presentations"),
        .other: DisplayRepresentation(title: "Other")
    ]
}

enum FileWidgetSelection: Equatable, Sendable {
    case all
    case category(FileWidgetCategory)

    var emptyStateContent: WidgetEmptyStateContent {
        .noPinnedFiles()
    }

    var emptyStateTitle: String {
        emptyStateContent.title
    }

    var emptyStateSubtitle: String {
        emptyStateContent.subtitle ?? ""
    }

    var emptyStateSystemImage: String {
        emptyStateContent.systemImage
    }

    var lockScreenEmptyLabel: String {
        emptyStateContent.lockScreenLabel
    }

    var headerTitle: String {
        switch self {
        case .all:
            return "Files"
        case .category(let category):
            return Self.title(for: category)
        }
    }

    var deepLinkURL: URL {
        URL(string: "sidebar://files")!
    }

    func filter(_ data: WidgetFileData) -> WidgetFileData {
        switch self {
        case .all:
            return data
        case .category(let category):
            let filteredFiles = data.files.filter {
                Self.normalizedCategory($0.category) == category.rawValue
            }
            return WidgetFileData(
                files: filteredFiles,
                totalCount: filteredFiles.count,
                lastUpdated: data.lastUpdated
            )
        }
    }

    private static func normalizedCategory(_ category: String?) -> String {
        guard let category else { return FileWidgetCategory.other.rawValue }
        switch category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "document", "documents":
            return FileWidgetCategory.documents.rawValue
        case "image", "images":
            return FileWidgetCategory.images.rawValue
        case "audio":
            return FileWidgetCategory.audio.rawValue
        case "video", "videos":
            return FileWidgetCategory.video.rawValue
        case "spreadsheet", "spreadsheets":
            return FileWidgetCategory.spreadsheets.rawValue
        case "report", "reports":
            return FileWidgetCategory.reports.rawValue
        case "presentation", "presentations":
            return FileWidgetCategory.presentations.rawValue
        default:
            return FileWidgetCategory.other.rawValue
        }
    }

    private static func title(for category: FileWidgetCategory) -> String {
        switch category {
        case .documents:
            return "Documents"
        case .images:
            return "Images"
        case .audio:
            return "Audio"
        case .video:
            return "Video"
        case .spreadsheets:
            return "Spreadsheets"
        case .reports:
            return "Reports"
        case .presentations:
            return "Presentations"
        case .other:
            return "Other"
        }
    }
}

struct FilesWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Files Widget"
    static var description = IntentDescription("Choose which files the widget should show.")

    @Parameter(title: "Scope", default: .all)
    var scope: FileWidgetScope

    @Parameter(title: "Category")
    var category: FileWidgetCategory?

    init() {
        scope = .all
    }

    init(selection: FileWidgetSelection) {
        switch selection {
        case .all:
            scope = .all
        case .category(let category):
            scope = .category
            self.category = category
        }
    }

    static var parameterSummary: some ParameterSummary {
        Switch(\.$scope) {
            Case(.category) {
                Summary("Show \(\.$category) files")
            }
            DefaultCase {
                Summary("Show \(\.$scope)")
            }
        }
    }

    var selection: FileWidgetSelection {
        switch scope {
        case .all:
            return .all
        case .category:
            if let category {
                return .category(category)
            }
            return .all
        }
    }
}

// MARK: - Open Files Intent

/// Intent to open the app to the files view
struct OpenFilesIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Files"
    static var description = IntentDescription("Opens sideBar to your files")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & OpensIntent {
        guard let url = URL(string: "sidebar://files") else {
            return .result()
        }
        return .result(opensIntent: OpenURLIntent(url))
    }
}

// MARK: - Open File Intent

/// Intent to open a specific file in the app
struct OpenFileIntent: AppIntent {
    static var title: LocalizedStringResource = "Open File"
    static var description = IntentDescription("Opens a specific file in sideBar")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "File ID")
    var fileId: String

    init() {}

    init(fileId: String) {
        self.fileId = fileId
    }

    func perform() async throws -> some IntentResult & OpensIntent {
        guard let url = URL(string: "sidebar://files/\(fileId)") else {
            return .result()
        }
        return .result(opensIntent: OpenURLIntent(url))
    }
}
