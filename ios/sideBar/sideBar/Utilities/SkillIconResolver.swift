import Foundation
import sideBarShared

/// Centralized skill icon resolver shared by Store, Settings, and Chat surfaces.
enum SkillIconResolver {
    private static let fallbackIcon = AppIcon.Skills.fallback

    private static let skillIcons: [String: AppIcon] = [
        "assistant-identity": AppIcon.Skills.assistantIdentity,
        "assistant-soul": AppIcon.Skills.assistantSoul,
        "audio-transcribe": AppIcon.Media.waveform,
        "conversations": AppIcon.Skills.conversations,
        "files": AppIcon.Skills.files,
        "memory": AppIcon.Skills.memory,
        "notes": AppIcon.Content.note,
        "product-feedback": AppIcon.Skills.productFeedback,
        "prompt-preview": AppIcon.Skills.promptPreview,
        "settings-other-preferences": AppIcon.Skills.settingsOtherPreferences,
        "settings-profile-user": AppIcon.Settings.profile,
        "subdomain-discover": AppIcon.Content.websiteFallback,
        "tasks": AppIcon.Domain.tasks,
        "ui-theme": AppIcon.Settings.theme,
        "web-crawler-policy": AppIcon.Skills.webCrawlerPolicy,
        "web-save": AppIcon.Skills.webSave,
        "web-search": AppIcon.Action.search,
        "youtube-download": AppIcon.Skills.youtubeDownload,
        "youtube-transcribe": AppIcon.Skills.youtubeTranscribe
    ]

    /// Backward-compatible fallback for older chat history where `skill_id` was not persisted.
    private static let toolDisplaySkillIDs: [String: String] = [
        "add website": "web-save",
        "archive note": "notes",
        "archive website": "web-save",
        "browse files": "files",
        "clear scratchpad": "notes",
        "clear task due date": "tasks",
        "complete task": "tasks",
        "crawler policy check": "web-crawler-policy",
        "create group": "tasks",
        "create note": "notes",
        "create note folder": "notes",
        "create project": "tasks",
        "create task": "tasks",
        "defer task": "tasks",
        "delete file": "files",
        "delete note": "notes",
        "delete note folder": "notes",
        "delete task": "tasks",
        "delete website": "web-save",
        "discover subdomains": "subdomain-discover",
        "download note": "notes",
        "download website": "web-save",
        "download youtube": "youtube-download",
        "edit note": "notes",
        "generate prompts": "prompt-preview",
        "get assistant identity": "assistant-identity",
        "get assistant soul": "assistant-soul",
        "get note": "notes",
        "get profile and user settings": "settings-profile-user",
        "get scratchpad": "notes",
        "list notes": "notes",
        "list tasks": "tasks",
        "list websites": "web-save",
        "memory tool": "memory",
        "move note": "notes",
        "move note folder": "notes",
        "pin file": "files",
        "pin note": "notes",
        "pin website": "web-save",
        "read file": "files",
        "read website": "web-save",
        "remove profile image": "settings-profile-user",
        "rename file": "files",
        "rename group": "tasks",
        "rename note": "notes",
        "rename note folder": "notes",
        "rename project": "tasks",
        "rename task": "tasks",
        "rename website": "web-save",
        "reset assistant identity": "assistant-identity",
        "reset assistant soul": "assistant-soul",
        "save website": "web-save",
        "search files": "files",
        "search tasks": "tasks",
        "set other preferences": "settings-other-preferences",
        "set task due date": "tasks",
        "set task repeat": "tasks",
        "set ui theme": "ui-theme",
        "submit bug report": "product-feedback",
        "submit feature request": "product-feedback",
        "transcribe audio": "audio-transcribe",
        "transcribe youtube": "youtube-transcribe",
        "update assistant identity": "assistant-identity",
        "update assistant soul": "assistant-soul",
        "update note": "notes",
        "update profile and user settings": "settings-profile-user",
        "update scratchpad": "notes",
        "update task notes": "tasks",
        "upload profile image": "settings-profile-user",
        "write file": "files"
    ]

    static func iconName(for skill: SkillItem) -> String {
        iconName(skillId: skill.id, iconKey: skill.iconKey)
    }

    static func iconName(for toolCall: ToolCall) -> String {
        appIcon(for: toolCall).rawValue
    }

    static func settingsIconName(for skill: SkillItem) -> String {
        switch normalized(skill.id) {
        case "conversations":
            return AppSection.chat.iconName
        case "notes":
            return AppSection.notes.iconName
        case "files":
            return AppSection.files.iconName
        case "web-save", "websites":
            return AppSection.websites.iconName
        default:
            return iconName(for: skill)
        }
    }

    static func iconName(skillId: String?, iconKey: String?) -> String {
        return appIcon(skillId: skillId, iconKey: iconKey).rawValue
    }

    static func appIcon(skillId: String?, iconKey: String?) -> AppIcon {
        if let iconKey, let icon = skillIcons[normalized(iconKey)] {
            return icon
        }
        if let skillId, let icon = skillIcons[normalized(skillId)] {
            return icon
        }
        return fallbackIcon
    }

    static func appIcon(for toolCall: ToolCall) -> AppIcon {
        appIcon(
            skillId: toolCall.skillId ?? skillId(forToolDisplayName: toolCall.name),
            iconKey: toolCall.iconKey
        )
    }

    static func skillId(forToolDisplayName name: String) -> String? {
        let normalizedName = normalized(name)
        guard !normalizedName.isEmpty else { return nil }
        return toolDisplaySkillIDs[normalizedName]
    }

    private static func normalized(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
