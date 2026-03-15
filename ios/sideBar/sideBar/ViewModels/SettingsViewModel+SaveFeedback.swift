import Foundation

@MainActor
extension SettingsViewModel {
    static func dateOnlyString(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    func setPrimaryProviderSaving(_ isSaving: Bool) {
        isSavingPrimaryProvider = isSaving
    }

    func setPrimaryProviderError(_ error: String?) {
        primaryProviderError = error
    }

    func recordCompletedSettingsSave() {
        settingsSaveCompletionCount += 1
    }
}
