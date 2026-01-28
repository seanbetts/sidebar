import { get } from 'svelte/store';
import { tasksStore } from '$lib/stores/tasks';

const REFRESH_DEBOUNCE_MS = 1000;
const RECONNECT_DELAY_MS = 3000;

let eventSource: EventSource | null = null;
let reconnectTimer: ReturnType<typeof setTimeout> | null = null;
let refreshTimer: ReturnType<typeof setTimeout> | null = null;
let activeUserId: string | null = null;

function clearRefreshTimer() {
	if (refreshTimer) {
		clearTimeout(refreshTimer);
		refreshTimer = null;
	}
}

function clearReconnectTimer() {
	if (reconnectTimer) {
		clearTimeout(reconnectTimer);
		reconnectTimer = null;
	}
}

function scheduleRefresh() {
	if (refreshTimer) return;
	refreshTimer = setTimeout(() => {
		refreshTimer = null;
		const state = get(tasksStore);
		void tasksStore.loadCounts(true);
		void tasksStore.load(state.selection, { force: true, silent: true, notify: false });
	}, REFRESH_DEBOUNCE_MS);
}

function handleChangeEvent(payload: any) {
	if (!payload || payload.scope !== 'tasks') return;
	scheduleRefresh();
}

function connect() {
	if (eventSource) return;
	eventSource = new EventSource('/api/v1/events');
	eventSource.addEventListener('change', (event) => {
		try {
			const payload = JSON.parse((event as MessageEvent).data);
			handleChangeEvent(payload);
		} catch {
			// Ignore malformed payloads.
		}
	});
	eventSource.onerror = () => {
		cleanup();
		if (!reconnectTimer) {
			reconnectTimer = setTimeout(() => {
				reconnectTimer = null;
				connect();
			}, RECONNECT_DELAY_MS);
		}
	};
}

function cleanup() {
	if (eventSource) {
		eventSource.close();
		eventSource = null;
	}
}

/**
 * Start task change events for the current user.
 */
export function startTaskEvents(userId: string | null) {
	if (typeof window === 'undefined') return;
	if (!userId) {
		stopTaskEvents();
		return;
	}
	if (activeUserId === userId && eventSource) return;
	activeUserId = userId;
	clearReconnectTimer();
	connect();
}

/**
 * Stop task change event stream and timers.
 */
export function stopTaskEvents() {
	activeUserId = null;
	clearReconnectTimer();
	clearRefreshTimer();
	cleanup();
}
