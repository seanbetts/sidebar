import Foundation

public struct AppIcon: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public extension AppIcon {
    enum Action {
        public static let add = AppIcon(rawValue: "plus")
        public static let close = AppIcon(rawValue: "xmark")
        public static let clearFilled = AppIcon(rawValue: "xmark.circle.fill")
        public static let more = AppIcon(rawValue: "ellipsis")
        public static let delete = AppIcon(rawValue: "trash")
        public static let share = AppIcon(rawValue: "square.and.arrow.up")
        public static let shareOnSquare = AppIcon(rawValue: "square.and.arrow.up.on.square")
        public static let download = AppIcon(rawValue: "square.and.arrow.down")
        public static let copy = AppIcon(rawValue: "doc.on.doc")
        public static let copyTitle = AppIcon(rawValue: "textformat")
        public static let copyURL = AppIcon(rawValue: "link")
        public static let rename = AppIcon(rawValue: "pencil")
        public static let compose = AppIcon(rawValue: "square.and.pencil")
        public static let move = AppIcon(rawValue: "arrow.forward.folder")
        public static let reorder = AppIcon(rawValue: "line.3.horizontal")
        public static let pin = AppIcon(rawValue: "pin")
        public static let unpin = AppIcon(rawValue: "pin.slash")
        public static let archive = AppIcon(rawValue: "archivebox")
        public static let unarchive = AppIcon(rawValue: "archivebox.fill")
        public static let search = AppIcon(rawValue: "magnifyingglass")
        public static let refresh = AppIcon(rawValue: "arrow.clockwise")
        public static let send = AppIcon(rawValue: "arrow.up")
        public static let attach = AppIcon(rawValue: "paperclip")
        public static let openExternal = AppIcon(rawValue: "arrow.up.right.square")
        public static let signOut = AppIcon(rawValue: "rectangle.portrait.and.arrow.right")
    }

    enum Domain {
        public static let chat = AppIcon(rawValue: "bubble")
        public static let notes = AppIcon(rawValue: "text.document")
        public static let tasks = AppIcon(rawValue: "checkmark.square")
        public static let websites = AppIcon(rawValue: "globe")
        public static let files = AppIcon(rawValue: "folder")
        public static let skillsStore = AppIcon(rawValue: "command.circle")
        public static let settings = AppIcon(rawValue: "square.grid.2x2")
        public static let memories = AppIcon(rawValue: "bookmark")
    }

    enum Navigation {
        public static let back = AppIcon(rawValue: "chevron.left")
        public static let forward = AppIcon(rawValue: "chevron.right")
        public static let chevronRight = AppIcon(rawValue: "chevron.right")
        public static let chevronDown = AppIcon(rawValue: "chevron.down")
        public static let pickerDisclosure = AppIcon(rawValue: "chevron.up.chevron.down")
        public static let expandWorkspace = AppIcon(rawValue: "arrow.up.right.and.arrow.down.left")
        public static let collapseWorkspace = AppIcon(rawValue: "arrow.down.left.and.arrow.up.right")
    }

    enum State {
        public static let success = AppIcon(rawValue: "checkmark")
        public static let successCircle = AppIcon(rawValue: "checkmark.circle")
        public static let successFilled = AppIcon(rawValue: "checkmark.circle.fill")
        public static let warning = AppIcon(rawValue: "exclamationmark.triangle")
        public static let warningFilled = AppIcon(rawValue: "exclamationmark.triangle.fill")
        public static let error = AppIcon(rawValue: "exclamationmark.circle")
        public static let errorFilled = AppIcon(rawValue: "exclamationmark.circle.fill")
        public static let emptyCircle = AppIcon(rawValue: "circle")
        public static let selectedCircle = AppIcon(rawValue: "circle.fill")
        public static let offline = AppIcon(rawValue: "wifi.slash")
        public static let networkWarning = AppIcon(rawValue: "wifi.exclamationmark")
        public static let syncing = AppIcon(rawValue: "arrow.triangle.2.circlepath")
        public static let retry = AppIcon(rawValue: "arrow.clockwise")
    }

    enum Content {
        public static let note = AppIcon(rawValue: "note.text")
        public static let textDocument = AppIcon(rawValue: "doc.text")
        public static let document = AppIcon(rawValue: "doc")
        public static let documentFilled = AppIcon(rawValue: "doc.fill")
        public static let folder = AppIcon(rawValue: "folder")
        public static let photo = AppIcon(rawValue: "photo")
        public static let taskList = AppIcon(rawValue: "list.bullet.rectangle")
        public static let websiteFallback = AppIcon(rawValue: "globe")
    }

    enum Media {
        public static let video = AppIcon(rawValue: "play.rectangle")
        public static let playFilled = AppIcon(rawValue: "play.circle.fill")
        public static let waveform = AppIcon(rawValue: "waveform")
        public static let captions = AppIcon(rawValue: "captions.bubble")
    }

    enum PDF {
        public static let fitPage = AppIcon(rawValue: "doc.viewfinder")
        public static let zoomIn = AppIcon(rawValue: "plus.magnifyingglass")
        public static let zoomOut = AppIcon(rawValue: "minus.magnifyingglass")
        public static let fitWidth = AppIcon(rawValue: "distribute.horizontal")
        public static let fitHeight = AppIcon(rawValue: "distribute.vertical")
    }

    enum Settings {
        public static let profile = AppIcon(rawValue: "person.crop.circle")
        public static let profileFilled = AppIcon(rawValue: "person.crop.circle.fill")
        public static let profileAdd = AppIcon(rawValue: "person.crop.circle.badge.plus")
        public static let user = AppIcon(rawValue: "person.line.dotted.person")
        public static let assistant = AppIcon(rawValue: "brain.fill")
        public static let credentials = AppIcon(rawValue: "key.horizontal")
        public static let credentialsFilled = AppIcon(rawValue: "key.horizontal.fill")
        public static let theme = AppIcon(rawValue: "paintpalette")
    }

    enum Skills {
        public static let fallback = AppIcon(rawValue: "puzzlepiece.extension")
        public static let categoryFallback = AppIcon(rawValue: "tag.fill")
        public static let tools = AppIcon(rawValue: "hammer")
        public static let assistantIdentity = AppIcon(rawValue: "person.crop.circle.badge.checkmark")
        public static let assistantSoul = AppIcon(rawValue: "sparkles")
        public static let conversations = AppIcon(rawValue: "bubble.left.and.bubble.right")
        public static let files = AppIcon(rawValue: "doc.on.doc")
        public static let memory = AppIcon(rawValue: "brain")
        public static let productFeedback = AppIcon(rawValue: "exclamationmark.bubble")
        public static let promptPreview = AppIcon(rawValue: "eye")
        public static let settingsOtherPreferences = AppIcon(rawValue: "gearshape")
        public static let webCrawlerPolicy = AppIcon(rawValue: "shield")
        public static let webSave = AppIcon(rawValue: "square.and.arrow.down")
        public static let webSearch = AppIcon(rawValue: "magnifyingglass")
        public static let youtubeDownload = AppIcon(rawValue: "play.rectangle")
        public static let youtubeTranscribe = AppIcon(rawValue: "captions.bubble")
    }
}
