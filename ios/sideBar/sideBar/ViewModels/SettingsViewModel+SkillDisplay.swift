import Foundation

@MainActor
extension SettingsViewModel {
    public func displayName(for skill: SkillItem) -> String {
        let normalizedSkillName = skill.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch skill.id {
        case "assistant-identity":
            return "\(assistantDisplayName)'s Identity"
        case "assistant-soul":
            return "\(assistantDisplayName)'s Soul"
        default:
            if normalizedSkillName == "assistant identity" || normalizedSkillName == "assisstant identity" {
                return "\(assistantDisplayName)'s Identity"
            }
            if normalizedSkillName == "assistant soul" || normalizedSkillName == "assisstant soul" {
                return "\(assistantDisplayName)'s Soul"
            }
            return skill.name
        }
    }

    public func displayDescription(for skill: SkillItem) -> String {
        let personalized = skill.description
            .replacingOccurrences(of: "{name}", with: assistantDisplayName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if personalized.hasSuffix(".") {
            return String(personalized.dropLast())
        }
        return personalized
    }
}
