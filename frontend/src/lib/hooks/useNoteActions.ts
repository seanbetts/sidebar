import { notesAPI } from '$lib/services/api';
import { treeStore } from '$lib/stores/tree';
import { logError } from '$lib/utils/errorHandling';

type NotesActionOptions = {
  scope?: string;
};

const defaultScope = (action: string) => `notesActions.${action}`;

/**
 * Provide reusable notes action handlers for pinned ordering.
 */
export function useNoteActions() {
  const updatePinnedOrder = async (
    order: string[],
    options: NotesActionOptions = {}
  ): Promise<boolean> => {
    treeStore.setNotePinnedOrder(order);
    try {
      await notesAPI.updatePinnedOrder(order);
      return true;
    } catch (error) {
      logError('Failed to update pinned order', error, {
        scope: options.scope ?? defaultScope('pinnedOrder')
      });
      return false;
    }
  };

  return {
    updatePinnedOrder
  };
}
