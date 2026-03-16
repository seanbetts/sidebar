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
		bindings.length = 0;
		vi.clearAllMocks();
	});

	it('scopes file processing jobs to the active user', async () => {
		const { startRealtime } = await import('$lib/realtime/realtime');

		await startRealtime('user-123');

		expect(bindings).toHaveLength(4);
		expect(bindings[3]).toMatchObject({
			event: '*',
			schema: 'public',
			table: 'file_processing_jobs',
			filter: 'user_id=eq.user-123'
		});
	});
});
