import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { useWebsiteActions } from '$lib/hooks/useWebsiteActions';

const { websitesAPI } = vi.hoisted(() => ({
	websitesAPI: {
		rename: vi.fn(),
		setPinned: vi.fn(),
		setArchived: vi.fn(),
		delete: vi.fn(),
		updatePinnedOrder: vi.fn()
	}
}));

const { websitesStore } = vi.hoisted(() => ({
	websitesStore: {
		loadById: vi.fn(),
		renameLocal: vi.fn(),
		setPinnedLocal: vi.fn(),
		setArchivedLocal: vi.fn(),
		removeLocal: vi.fn(),
		updateActiveLocal: vi.fn(),
		clearActive: vi.fn(),
		subscribe: vi.fn()
	}
}));

const { dispatchCacheEvent } = vi.hoisted(() => ({
	dispatchCacheEvent: vi.fn()
}));

const { logError } = vi.hoisted(() => ({
	logError: vi.fn()
}));

const { toast } = vi.hoisted(() => ({
	toast: {
		error: vi.fn()
	}
}));

vi.mock('$lib/services/api', () => ({ websitesAPI }));
vi.mock('$lib/stores/websites', () => ({ websitesStore }));
vi.mock('$lib/utils/cacheEvents', () => ({ dispatchCacheEvent }));
vi.mock('$lib/utils/errorHandling', () => ({ logError }));
vi.mock('svelte-sonner', () => ({ toast }));
vi.mock('$lib/stores/ingestion-viewer', () => ({
	ingestionViewerStore: { clearActive: vi.fn() }
}));
vi.mock('$lib/stores/editor', () => ({
	editorStore: { reset: vi.fn() },
	currentNoteId: { set: vi.fn() }
}));

describe('useWebsiteActions', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.useRealTimers();
	});

	afterEach(() => {
		vi.useRealTimers();
	});

	it('retries transient rename failures before surfacing an error', async () => {
		vi.useFakeTimers();
		const transientError = Object.assign(new Error('Service unavailable'), { status: 503 });
		websitesAPI.rename.mockRejectedValueOnce(transientError).mockResolvedValueOnce(undefined);

		const { renameWebsite } = useWebsiteActions();
		const renamePromise = renameWebsite('website-1', 'Renamed website', { updateActive: true });

		await vi.runAllTimersAsync();

		await expect(renamePromise).resolves.toBe(true);
		expect(websitesAPI.rename).toHaveBeenCalledTimes(2);
		expect(websitesStore.renameLocal).toHaveBeenCalledWith('website-1', 'Renamed website');
		expect(websitesStore.updateActiveLocal).toHaveBeenCalledWith({ title: 'Renamed website' });
		expect(dispatchCacheEvent).toHaveBeenCalledWith('website.renamed');
		expect(toast.error).not.toHaveBeenCalled();
		expect(logError).not.toHaveBeenCalled();
	});
});
