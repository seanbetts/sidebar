import { websitesStore } from '$lib/stores/websites';
import { websitesAPI } from '$lib/services/api';
import { dispatchCacheEvent } from '$lib/utils/cacheEvents';
import { logError } from '$lib/utils/errorHandling';
import { ingestionViewerStore } from '$lib/stores/ingestion-viewer';
import { editorStore, currentNoteId } from '$lib/stores/editor';
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
      await websitesAPI.rename(websiteId, title);
      websitesStore.renameLocal?.(websiteId, title);
      if (options.updateActive) {
        websitesStore.updateActiveLocal?.({ title });
      }
      dispatchCacheEvent('website.renamed');
      return true;
    } catch (error) {
      toast.error('Failed to rename website');
      logError('Failed to rename website', error, {
        scope: options.scope ?? defaultScope('rename'),
        websiteId
      });
      return false;
    }
  };

  const pinWebsite = async (
    websiteId: string,
    pinned: boolean,
    options: WebsiteActionOptions = {}
  ): Promise<boolean> => {
    try {
      await websitesAPI.setPinned(websiteId, pinned);
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
      toast.error('Failed to pin website');
      logError('Failed to update website pin', error, {
        scope: options.scope ?? defaultScope('pin'),
        websiteId,
        pinned
      });
      return false;
    }
  };

  const archiveWebsite = async (
    websiteId: string,
    archived: boolean,
    options: WebsiteActionOptions = {}
  ): Promise<boolean> => {
    try {
      await websitesAPI.setArchived(websiteId, archived);
      websitesStore.setArchivedLocal?.(websiteId, archived);
      dispatchCacheEvent('website.archived');
      if (options.clearActiveOnArchive && archived) {
        websitesStore.clearActive();
      } else if (options.updateActive) {
        websitesStore.updateActiveLocal?.({ archived });
      }
      return true;
    } catch (error) {
      toast.error('Failed to archive website');
      logError('Failed to archive website', error, {
        scope: options.scope ?? defaultScope('archive'),
        websiteId,
        archived
      });
      return false;
    }
  };

  const deleteWebsite = async (
    websiteId: string,
    options: WebsiteActionOptions = {}
  ): Promise<boolean> => {
    try {
      await websitesAPI.delete(websiteId);
      websitesStore.removeLocal?.(websiteId);
      dispatchCacheEvent('website.deleted');
      if (options.clearActiveOnDelete) {
        websitesStore.clearActive();
      }
      return true;
    } catch (error) {
      toast.error('Failed to delete website');
      logError('Failed to delete website', error, {
        scope: options.scope ?? defaultScope('delete'),
        websiteId
      });
      return false;
    }
  };

  const updatePinnedOrder = async (
    order: string[],
    options: WebsiteActionOptions = {}
  ): Promise<boolean> => {
    websitesStore.setPinnedOrderLocal?.(order);
    try {
      await websitesAPI.updatePinnedOrder(order);
      return true;
    } catch (error) {
      logError('Failed to update pinned order', error, {
        scope: options.scope ?? defaultScope('pinnedOrder')
      });
      return false;
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
