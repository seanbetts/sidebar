import { get } from 'svelte/store';
import { websitesStore } from '$lib/stores/websites';
import { websitesAPI } from '$lib/services/api';
import { dispatchCacheEvent } from '$lib/utils/cacheEvents';
import { logError, parseError } from '$lib/utils/errorHandling';
import { ingestionViewerStore } from '$lib/stores/ingestion-viewer';
import { editorStore, currentNoteId } from '$lib/stores/editor';
import { retryForegroundMutation } from '$lib/utils/foregroundMutationRetry';
import { toast } from 'svelte-sonner';

type WebsiteActionOptions = {
	scope?: string;
	updateActive?: boolean;
	clearActiveOnArchive?: boolean;
	clearActiveOnDelete?: boolean;
};

const defaultScope = (action: string) => `websiteActions.${action}`;

/**
 * Provide reusable website action handlers for panels and viewers.
 *
 * @returns Website action handlers.
 */
export function useWebsiteActions() {
	const surfaceMutationError = (
		fallbackMessage: string,
		error: unknown,
		context: Record<string, unknown>
	): false => {
		const parsed = parseError(error);
		toast.error(parsed.message || fallbackMessage);
		logError(fallbackMessage, error, context);
		return false;
	};

	const openWebsite = async (websiteId: string) => {
		ingestionViewerStore.clearActive();
		editorStore.reset();
		currentNoteId.set(null);
		await websitesStore.loadById(websiteId);
	};

	const renameWebsite = async (
		websiteId: string,
		title: string,
		options: WebsiteActionOptions = {}
	): Promise<boolean> => {
		try {
			await retryForegroundMutation(() => websitesAPI.rename(websiteId, title));
			websitesStore.renameLocal?.(websiteId, title);
			if (options.updateActive) {
				websitesStore.updateActiveLocal?.({ title });
			}
			dispatchCacheEvent('website.renamed');
			return true;
		} catch (error) {
			return surfaceMutationError('Failed to rename website', error, {
				scope: options.scope ?? defaultScope('rename'),
				websiteId
			});
		}
	};

	const pinWebsite = async (
		websiteId: string,
		pinned: boolean,
		options: WebsiteActionOptions = {}
	): Promise<boolean> => {
		try {
			await retryForegroundMutation(() => websitesAPI.setPinned(websiteId, pinned));
			websitesStore.setPinnedLocal?.(websiteId, pinned);
			if (options.updateActive) {
				websitesStore.updateActiveLocal?.({
					pinned,
					...(pinned ? { archived: false } : {})
				});
			}
			dispatchCacheEvent('website.pinned');
			return true;
		} catch (error) {
			return surfaceMutationError('Failed to update website pin', error, {
				scope: options.scope ?? defaultScope('pin'),
				websiteId,
				pinned
			});
		}
	};

	const archiveWebsite = async (
		websiteId: string,
		archived: boolean,
		options: WebsiteActionOptions = {}
	): Promise<boolean> => {
		try {
			await retryForegroundMutation(() => websitesAPI.setArchived(websiteId, archived));
			websitesStore.setArchivedLocal?.(websiteId, archived);
			dispatchCacheEvent('website.archived');
			if (options.clearActiveOnArchive && archived) {
				websitesStore.clearActive();
			} else if (options.updateActive) {
				websitesStore.updateActiveLocal?.({ archived });
			}
			return true;
		} catch (error) {
			return surfaceMutationError('Failed to archive website', error, {
				scope: options.scope ?? defaultScope('archive'),
				websiteId,
				archived
			});
		}
	};

	const deleteWebsite = async (
		websiteId: string,
		options: WebsiteActionOptions = {}
	): Promise<boolean> => {
		try {
			await retryForegroundMutation(() => websitesAPI.delete(websiteId));
			websitesStore.removeLocal?.(websiteId);
			dispatchCacheEvent('website.deleted');
			if (options.clearActiveOnDelete) {
				websitesStore.clearActive();
			}
			return true;
		} catch (error) {
			return surfaceMutationError('Failed to delete website', error, {
				scope: options.scope ?? defaultScope('delete'),
				websiteId
			});
		}
	};

	const updatePinnedOrder = async (
		order: string[],
		options: WebsiteActionOptions = {}
	): Promise<boolean> => {
		const previousOrder = get(websitesStore)
			.items.filter((item) => item.pinned)
			.sort((a, b) => (a.pinned_order ?? Infinity) - (b.pinned_order ?? Infinity))
			.map((item) => item.id);
		websitesStore.setPinnedOrderLocal?.(order);
		try {
			await retryForegroundMutation(() => websitesAPI.updatePinnedOrder(order));
			return true;
		} catch (error) {
			websitesStore.setPinnedOrderLocal?.(previousOrder);
			return surfaceMutationError('Failed to update pinned order', error, {
				scope: options.scope ?? defaultScope('pinnedOrder')
			});
		}
	};

	return {
		openWebsite,
		renameWebsite,
		pinWebsite,
		archiveWebsite,
		deleteWebsite,
		updatePinnedOrder
	};
}
