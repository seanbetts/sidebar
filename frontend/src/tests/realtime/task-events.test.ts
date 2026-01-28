import { describe, expect, it, vi } from 'vitest';

vi.mock('$lib/stores/tasks', () => {
	return {
		tasksStore: {
			loadCounts: vi.fn(async () => undefined),
			load: vi.fn(async () => undefined),
			subscribe: (fn: (value: { selection: { type: string } }) => void) => {
				fn({ selection: { type: 'today' } });
				return () => undefined;
			}
		}
	};
});

import { tasksStore } from '$lib/stores/tasks';
import { startTaskEvents, stopTaskEvents } from '$lib/realtime/task_events';

describe('task events', () => {
	it('connects and refreshes on change event', async () => {
		const listeners = new Map<string, (event: MessageEvent) => void>();
		class FakeEventSource {
			url: string;
			onerror: (() => void) | null = null;
			constructor(url: string) {
				this.url = url;
			}
			addEventListener(type: string, handler: (event: MessageEvent) => void) {
				listeners.set(type, handler);
			}
			close() {
				return;
			}
		}

		// @ts-expect-error - test global override
		globalThis.EventSource = FakeEventSource;
		// @ts-expect-error - test global override
		globalThis.window = {};

		startTaskEvents('user-1');
		const handler = listeners.get('change');
		expect(handler).toBeDefined();
		handler?.(
			new MessageEvent('change', {
				data: JSON.stringify({ scope: 'tasks' })
			})
		);
		await new Promise((resolve) => setTimeout(resolve, 1100));
		expect(tasksStore.loadCounts).toHaveBeenCalled();
		expect(tasksStore.load).toHaveBeenCalled();
		stopTaskEvents();
	});
});
