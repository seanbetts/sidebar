import type { TasksState } from '$lib/stores/tasks';

type NoticeField = 'syncNotice' | 'conflictNotice';

/**
 * Build a notice setter with auto-clear behavior.
 */
export const createNotice = (
	field: NoticeField,
	updateState: (updater: (state: TasksState) => TasksState) => void,
	clearMs: number | null = 6000
) => {
	let syncNoticeTimer: ReturnType<typeof setTimeout> | null = null;
	return (message: string) => {
		if (syncNoticeTimer) {
			clearTimeout(syncNoticeTimer);
		}
		updateState((state) => ({ ...state, [field]: message }));
		if (clearMs === null) {
			return;
		}
		syncNoticeTimer = setTimeout(() => {
			updateState((state) => ({ ...state, [field]: '' }));
		}, clearMs);
	};
};
