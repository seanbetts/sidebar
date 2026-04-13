import { afterEach, describe, expect, it, vi } from 'vitest';

const setAuth = vi.fn();
const subscribe = vi.fn();
const removeChannel = vi.fn();
const bindings: Array<Record<string, unknown>> = [];
const channel = vi.fn((_name: string) => {
	const instance = {
		on: vi.fn((_event, config, _handler) => {
			bindings.push(config);
			return instance;
		}),
		subscribe
	};
	return instance;
});

vi.mock('$lib/supabase', () => ({
	getSupabaseClient: () => ({
		realtime: {
			setAuth
		},
		channel,
		removeChannel
	})
}));

vi.mock('$lib/stores/auth', () => ({
	session: {
		subscribe: (run: (value: { access_token: string } | null) => void) => {
			run({ access_token: 'token-123' });
			return () => {};
		}
	}
}));

const { sidebarSectionStore } = vi.hoisted(() => {
	let value: 'notes' | 'files' | 'websites' | 'chat' | 'tasks' = 'notes';
	const subscribers = new Set<(next: typeof value) => void>();
	return {
		sidebarSectionStore: {
			subscribe(run: (next: typeof value) => void) {
				run(value);
				subscribers.add(run);
				return () => subscribers.delete(run);
			},
			set(next: typeof value) {
				value = next;
				subscribers.forEach((run) => run(value));
			},
			reset() {
				value = 'notes';
				subscribers.forEach((run) => run(value));
			}
		}
	};
});

vi.mock('$lib/stores/sidebar-section', () => ({ sidebarSectionStore }));

vi.mock('$lib/stores/websites', () => ({
	websitesStore: {
		removeLocal: vi.fn(),
		upsertFromRealtime: vi.fn()
	}
}));

vi.mock('$lib/stores/tree', () => ({
	treeStore: {
		removeNode: vi.fn(),
		addNoteNode: vi.fn(),
		renameNoteNode: vi.fn(),
		moveNoteNode: vi.fn(),
		updateNoteFields: vi.fn()
	}
}));

vi.mock('$lib/stores/ingestion', () => ({
	ingestionStore: {
		removeItem: vi.fn(),
		revalidateInBackground: vi.fn(),
		updateFileFields: vi.fn(),
		updateJob: vi.fn()
	}
}));

vi.mock('$lib/stores/ingestion-viewer', () => ({
	ingestionViewerStore: {
		updateActiveJob: vi.fn()
	}
}));

vi.mock('$lib/stores/scratchpad', () => ({
	scratchpadStore: {
		getCachedContent: vi.fn(() => null),
		setCachedContent: vi.fn(),
		bump: vi.fn()
	}
}));

describe('file job realtime subscriptions', () => {
	afterEach(async () => {
		const { stopRealtime } = await import('$lib/realtime/realtime');
		stopRealtime();
		sidebarSectionStore.reset();
		bindings.length = 0;
		vi.clearAllMocks();
	});

	it('subscribes only to notes by default', async () => {
		const { startRealtime } = await import('$lib/realtime/realtime');

		await startRealtime('user-123');

		expect(bindings).toHaveLength(1);
		expect(bindings[0]).toMatchObject({
			event: '*',
			schema: 'public',
			table: 'notes',
			filter: 'user_id=eq.user-123'
		});
	});

	it('subscribes to file processing jobs only when the files section becomes active', async () => {
		const { startRealtime } = await import('$lib/realtime/realtime');

		await startRealtime('user-123');
		bindings.length = 0;

		sidebarSectionStore.set('files');

		expect(bindings).toHaveLength(2);
		expect(bindings[1]).toMatchObject({
			event: '*',
			schema: 'public',
			table: 'file_processing_jobs',
			filter: 'user_id=eq.user-123'
		});
	});
});
