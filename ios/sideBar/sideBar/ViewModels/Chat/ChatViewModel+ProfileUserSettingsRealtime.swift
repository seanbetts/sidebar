import Foundation

extension ChatViewModel {
    func handleProfileUserSettingsUpdated(_ event: ChatStreamEvent) {
        _ = event
        onAssistantSettingsUpdated?(
            AssistantSettingsRealtimeUpdate(
                assistantIdentity: nil,
                assistantIdentityMeta: nil,
                assistantSoul: nil,
                assistantSoulMeta: nil,
                requiresRefresh: true
            )
        )
    }
}
