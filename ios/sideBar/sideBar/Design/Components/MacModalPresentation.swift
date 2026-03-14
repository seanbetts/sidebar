import CoreGraphics

enum MacPanelType: Equatable {
    case compactPopover
    case compactSheet
    case chooserSheet
    case editorSheet
    case decisionSheet
    case largeInspectorSheet
}

enum MacModalWidthPreset: Equatable {
    case narrow
    case medium
    case wide
    case inspector
}

func macModalWidthPreset(for type: MacPanelType) -> MacModalWidthPreset {
    switch type {
    case .compactPopover, .compactSheet, .decisionSheet:
        return .narrow
    case .chooserSheet:
        return .medium
    case .editorSheet:
        return .wide
    case .largeInspectorSheet:
        return .inspector
    }
}

func macModalFrameWidth(for type: MacPanelType) -> CGFloat {
    switch macModalWidthPreset(for: type) {
    case .narrow:
        return 420
    case .medium:
        return 520
    case .wide:
        return 640
    case .inspector:
        return 960
    }
}

func settingsMacPresentationPanelType() -> MacPanelType {
    .largeInspectorSheet
}

func taskNotesMacPanelType() -> MacPanelType {
    .editorSheet
}

func renameItemMacPanelType() -> MacPanelType {
    .compactSheet
}
