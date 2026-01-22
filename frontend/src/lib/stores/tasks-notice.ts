import type { TasksState } from '$lib/stores/tasks';

/**
 * Build a sync notice setter with auto-clear behavior.
 */
export const createSyncNotice = (
	updateState: (updater: (state: TasksState) => TasksState) => void
) => {
	let syncNoticeTimer: ReturnType<typeof setTimeout> | null = null;
	return (message: string) => {
		if (syncNoticeTimer) {
			clearTimeout(syncNoticeTimer);
		}
		updateState((state) => ({ ...state, syncNotice: message }));
		syncNoticeTimer = setTimeout(() => {
			updateState((state) => ({ ...state, syncNotice: '' }));
		}, 6000);
	};
};
