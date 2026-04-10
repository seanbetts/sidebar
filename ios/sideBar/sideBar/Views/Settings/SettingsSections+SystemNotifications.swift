import Foundation
import SwiftUI

extension UserSettingsView {
    var settingsSignature: String {
        guard let settings = viewModel.settings else {
            return "none"
        }
        return [
            settings.userId,
            settings.communicationStyle ?? "",
            settings.workingRelationship ?? ""
        ].compactMap { $0 }.joined(separator: "|")
    }

    var systemAutosaveSignature: String {
        [
            communicationStyle,
            workingRelationship
        ].joined(separator: "|")
    }

    var isDraftDirty: Bool {
        guard let settings = viewModel.settings else { return false }
        return communicationStyle != (settings.communicationStyle ?? "")
            || workingRelationship != (settings.workingRelationship ?? "")
    }

    func syncDraftsFromSettings(_ settings: UserSettings?) {
        guard let settings else { return }
        let shouldSync = SettingsDraftSynchronizer.shouldSyncDrafts(
            hasLoadedDrafts: hasLoadedDrafts,
            isDraftDirty: isDraftDirty,
            previousUserId: draftsUserId,
            nextUserId: settings.userId
        )
        if !shouldSync {
            return
        }
        if SettingsDraftSynchronizer.normalizedUserId(draftsUserId)
            != SettingsDraftSynchronizer.normalizedUserId(settings.userId) {
            autosaveController.cancelPendingAutosave()
        }
        isSyncingDrafts = true
        communicationStyle = settings.communicationStyle ?? ""
        workingRelationship = settings.workingRelationship ?? ""
        draftsUserId = settings.userId
        hasLoadedDrafts = true
        isSyncingDrafts = false
    }

    func scheduleAutosave() {
        autosaveController.scheduleAutosave(
            hasLoadedDrafts: hasLoadedDrafts,
            isSyncingDrafts: isSyncingDrafts,
            isDraftDirty: isDraftDirty
        ) {
            await viewModel.saveUserSettings(
                communicationStyle: communicationStyle,
                workingRelationship: workingRelationship
            )
        }
    }

    func flushPendingSystemAutosave() {
        let canFlush = Self.shouldFlushAutosaveOnDisappear(
            hasLoadedDrafts: hasLoadedDrafts,
            isSyncingDrafts: isSyncingDrafts,
            isDraftDirty: isDraftDirty,
            isSavingSystem: viewModel.isSavingSystem,
            isAutosaveSaving: autosaveController.isAutosaveSaving
        )
        autosaveController.flushPendingAutosave(
            shouldFlush: canFlush
        ) {
            await viewModel.saveUserSettings(
                communicationStyle: communicationStyle,
                workingRelationship: workingRelationship
            )
        }
    }
}
