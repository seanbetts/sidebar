import { get } from 'svelte/store';
import { currentNoteId, editorStore } from '$lib/stores/editor';
import { ingestionStore } from '$lib/stores/ingestion';
import { ingestionViewerStore } from '$lib/stores/ingestion-viewer';
import { websitesStore } from '$lib/stores/websites';
import { ingestionAPI } from '$lib/services/api';
import { dispatchCacheEvent } from '$lib/utils/cacheEvents';

export type IngestionUploadHandlers = {
  handleUploadFileClick: (input: HTMLInputElement | null) => void;
  handleFileSelected: (event: Event) => Promise<void>;
  handleAddYouTube: () => void;
  confirmAddYouTube: () => Promise<void>;
  handlePendingUpload: (pendingUploadId: string | null, setPendingUploadId: (id: string | null) => void) => void;
};

export type IngestionUploadState = {
  getIsUploadingFile: () => boolean;
  setIsUploadingFile: (value: boolean) => void;
  getIsAddingYoutube: () => boolean;
  setIsAddingYoutube: (value: boolean) => void;
  getYouTubeUrl: () => string;
  setYouTubeUrl: (value: string) => void;
  setYouTubeDialogOpen: (value: boolean) => void;
  setPendingUploadId: (value: string | null) => void;
  onError: (title: string, message: string) => void;
};

/**
 * Provide ingestion upload handlers bound to local UI state.
 *
 * @param state UI state helpers for ingestion uploads.
 * @returns Upload event handlers.
 */
export function useIngestionUploads(state: IngestionUploadState): IngestionUploadHandlers {
  const handleUploadFileClick = (input: HTMLInputElement | null) => {
    input?.click();
  };

  const handleFileSelected = async (event: Event) => {
    const input = event.target as HTMLInputElement;
    const selected = input.files?.[0];
    if (!selected || state.getIsUploadingFile()) return;

    const tempId = `upload-${crypto.randomUUID?.() ?? `${Date.now()}-${Math.random().toString(16).slice(2)}`}`;
    state.setIsUploadingFile(true);
    const localItem = ingestionStore.addLocalUpload({
      id: tempId,
      name: selected.name,
      type: selected.type,
      size: selected.size
    });
    ingestionViewerStore.setLocalActive(localItem);
    try {
      const { file_id } = await ingestionAPI.upload(selected, (progress) => {
        ingestionStore.updateLocalUploadProgress(tempId, progress);
        ingestionViewerStore.updateActiveJob(tempId, {
          status: 'uploading',
          stage: 'uploading',
          progress,
          user_message: `Uploading ${Math.round(progress)}%`
        });
      });
      ingestionStore.removeLocalUpload(tempId);
      const meta = await ingestionAPI.get(file_id);
      ingestionStore.upsertItem({
        file: meta.file,
        job: meta.job,
        recommended_viewer: meta.recommended_viewer
      });
      dispatchCacheEvent('file.uploaded');
      websitesStore.clearActive();
      editorStore.reset();
      currentNoteId.set(null);
      state.setPendingUploadId(file_id);
      ingestionViewerStore.open(file_id);
    } catch (error) {
      ingestionStore.removeLocalUpload(tempId);
      ingestionViewerStore.updateActiveJob(tempId, {
        status: 'failed',
        stage: 'failed',
        user_message: error instanceof Error ? error.message : 'Failed to upload file.'
      });
      const message =
        error instanceof Error && error.message ? error.message : 'Failed to upload file. Please try again.';
      state.onError('Unable to upload file', message);
    } finally {
      state.setIsUploadingFile(false);
      if (input) {
        input.value = '';
      }
    }
  };

  const handleAddYouTube = () => {
    state.setYouTubeUrl('');
    state.setYouTubeDialogOpen(true);
  };

  const confirmAddYouTube = async () => {
    const url = state.getYouTubeUrl().trim();
    if (!url || state.getIsAddingYoutube()) return;

    const tempId = `youtube-${crypto.randomUUID?.() ?? `${Date.now()}-${Math.random().toString(16).slice(2)}`}`;
    state.setIsAddingYoutube(true);
    const localItem = ingestionStore.addLocalSource({
      id: tempId,
      name: 'YouTube video',
      mime: 'video/youtube',
      url
    });
    ingestionViewerStore.setLocalActive(localItem);
    try {
      const { file_id } = await ingestionAPI.ingestYoutube(url);
      ingestionStore.removeLocalUpload(tempId);
      const meta = await ingestionAPI.get(file_id);
      ingestionStore.upsertItem({
        file: meta.file,
        job: meta.job,
        recommended_viewer: meta.recommended_viewer
      });
      dispatchCacheEvent('file.uploaded');
      websitesStore.clearActive();
      editorStore.reset();
      currentNoteId.set(null);
      state.setPendingUploadId(file_id);
      ingestionViewerStore.open(file_id);
      state.setYouTubeDialogOpen(false);
    } catch (error) {
      ingestionStore.removeLocalUpload(tempId);
      ingestionViewerStore.updateActiveJob(tempId, {
        status: 'failed',
        stage: 'failed',
        user_message: error instanceof Error ? error.message : 'Failed to add YouTube video.'
      });
      const message =
        error instanceof Error && error.message
          ? error.message
          : 'Failed to add YouTube video. Please try again.';
      state.onError('Unable to add YouTube video', message);
    } finally {
      state.setIsAddingYoutube(false);
    }
  };

  const handlePendingUpload = (
    pendingUploadId: string | null,
    setPendingUploadId: (id: string | null) => void
  ) => {
    if (!pendingUploadId) return;
    const item = get(ingestionStore).items.find(entry => entry.file.id === pendingUploadId);
    if (item?.job.status === 'ready' && item.recommended_viewer) {
      ingestionViewerStore.open(pendingUploadId);
      setPendingUploadId(null);
    } else if (item?.job.status === 'failed') {
      setPendingUploadId(null);
    }
  };

  return {
    handleUploadFileClick,
    handleFileSelected,
    handleAddYouTube,
    confirmAddYouTube,
    handlePendingUpload
  };
}
