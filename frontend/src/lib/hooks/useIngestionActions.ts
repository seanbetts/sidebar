import { get } from 'svelte/store';
import type { IngestionListItem } from '$lib/types/ingestion';
import { ingestionAPI } from '$lib/services/api';
import { ingestionStore } from '$lib/stores/ingestion';
import { ingestionViewerStore } from '$lib/stores/ingestion-viewer';
import { dispatchCacheEvent } from '$lib/utils/cacheEvents';
import { logError } from '$lib/utils/errorHandling';

type IngestionActionOptions = {
  scope?: string;
};

const defaultScope = (action: string) => `ingestionActions.${action}`;

/**
 * Provide reusable ingestion action handlers for file panels.
 *
 * @returns Ingestion action handlers.
 */
export function useIngestionActions() {
  const deleteIngestion = async (
    fileId: string,
    options: IngestionActionOptions = {}
  ): Promise<boolean> => {
    try {
      await ingestionAPI.delete(fileId);
      const active = get(ingestionViewerStore).active;
      if (active?.file.id === fileId) {
        ingestionViewerStore.clearActive();
      }
      dispatchCacheEvent('file.deleted');
      ingestionStore.removeItem(fileId);
      return true;
    } catch (error) {
      logError('Failed to delete ingestion', error, {
        scope: options.scope ?? defaultScope('delete'),
        fileId
      });
      return false;
    }
  };

  const updatePinned = async (
    fileId: string,
    pinned: boolean,
    options: IngestionActionOptions = {}
  ): Promise<boolean> => {
    try {
      await ingestionAPI.setPinned(fileId, pinned);
      ingestionStore.updatePinned(fileId, pinned);
      ingestionViewerStore.updatePinned(fileId, pinned);
      return true;
    } catch (error) {
      logError('Failed to update pin', error, {
        scope: options.scope ?? defaultScope('pin'),
        fileId,
        pinned
      });
      return false;
    }
  };

  const updatePinnedOrder = async (
    order: string[],
    options: IngestionActionOptions = {}
  ): Promise<boolean> => {
    ingestionStore.setPinnedOrder(order);
    try {
      await ingestionAPI.updatePinnedOrder(order);
      return true;
    } catch (error) {
      logError('Failed to update pinned order', error, {
        scope: options.scope ?? defaultScope('pinnedOrder')
      });
      return false;
    }
  };

  const downloadFile = async (
    item: IngestionListItem,
    options: IngestionActionOptions = {}
  ): Promise<boolean> => {
    if (!item.recommended_viewer) return false;
    try {
      const response = await ingestionAPI.getContent(item.file.id, item.recommended_viewer);
      const blob = await response.blob();
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = item.file.filename_original;
      link.click();
      URL.revokeObjectURL(url);
      return true;
    } catch (error) {
      logError('Failed to download file', error, {
        scope: options.scope ?? defaultScope('download'),
        fileId: item.file.id
      });
      return false;
    }
  };

  const renameFile = async (
    fileId: string,
    filename: string,
    options: IngestionActionOptions = {}
  ): Promise<boolean> => {
    try {
      await ingestionAPI.rename(fileId, filename);
      ingestionStore.updateFilename(fileId, filename);
      ingestionViewerStore.updateFilename(fileId, filename);
      return true;
    } catch (error) {
      logError('Failed to rename ingestion', error, {
        scope: options.scope ?? defaultScope('rename'),
        fileId
      });
      return false;
    }
  };

  return {
    deleteIngestion,
    updatePinned,
    updatePinnedOrder,
    downloadFile,
    renameFile
  };
}
