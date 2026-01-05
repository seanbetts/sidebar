import { writable, get } from 'svelte/store';
import { handleFetchError, logError } from '$lib/utils/errorHandling';

export interface EditorState {
  currentNoteId: string | null;
  currentNotePath: string | null;
  currentNoteName: string | null;
  content: string;
  originalContent: string;  // For dirty checking
  isDirty: boolean;
  isSaving: boolean;
  isLoading: boolean;
  lastSaved: Date | null;
  saveError: string | null;
  basePath: string;
  isReadOnly: boolean;
  lastUpdateSource: 'ai' | 'user' | null;
}

function createEditorStore() {
  const { subscribe, set, update } = writable<EditorState>({
    currentNoteId: null,
    currentNotePath: null,
    currentNoteName: null,
    content: '',
    originalContent: '',
    isDirty: false,
    isSaving: false,
    isLoading: false,
    lastSaved: null,
    saveError: null,
    basePath: 'notes',
    isReadOnly: false,
    lastUpdateSource: null
  });

  return {
    subscribe,

    async loadNote(
      basePath: string,
      path: string,
      options?: { source?: 'ai' | 'user' }
    ) {
      update(state => ({ ...state, isLoading: true, saveError: null }));

      try {
        const response = basePath === 'notes'
          ? await fetch(`/api/v1/notes/${path}`)
          : await fetch(`/api/v1/files/content?basePath=${basePath}&path=${encodeURIComponent(path)}`);

        if (!response.ok) {
          await handleFetchError(response);
        }

        const data = await response.json();

        update(state => ({
          ...state,
          currentNoteId: path,
          currentNotePath: data.path,
          currentNoteName: data.name,
          content: data.content,
          originalContent: data.content,
          isDirty: false,
          isLoading: false,
          basePath,
          isReadOnly: false,
          lastUpdateSource: options?.source ?? null
        }));
      } catch (error) {
        logError('Failed to load note', error, { basePath, path });
        update(state => ({
          ...state,
          isLoading: false,
          saveError: 'Failed to load note'
        }));
      }
    },

    updateContent(newContent: string) {
      update(state => {
        if (state.isReadOnly) {
          return state;
        }
        return {
          ...state,
          content: newContent,
          isDirty: newContent !== state.originalContent,
          lastUpdateSource: null
        };
      });
    },

    updateNoteName(newName: string) {
      update(state => ({
        ...state,
        currentNoteName: newName,
        lastUpdateSource: null
      }));
    },

    async saveNote() {
      const state = get({ subscribe });

      if (state.isReadOnly || !state.currentNoteId || !state.isDirty) return;

      update(s => ({ ...s, isSaving: true, saveError: null }));

      try {
        const response = state.basePath === 'notes'
          ? await fetch(`/api/v1/notes/${state.currentNoteId}`, {
              method: 'PATCH',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ content: state.content })
            })
          : await fetch('/api/v1/files/content', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({
                basePath: state.basePath,
                path: state.currentNoteId,
                content: state.content
              })
            });

        if (!response.ok) {
          await handleFetchError(response);
        }

        update(s => ({
          ...s,
          originalContent: s.content,
          isDirty: false,
          isSaving: false,
          lastSaved: new Date(),
          saveError: null,
          lastUpdateSource: null
        }));
      } catch (error) {
        logError('Failed to save note', error, {
          basePath: state.basePath,
          noteId: state.currentNoteId
        });
        update(s => ({
          ...s,
          isSaving: false,
          saveError: 'Failed to save note',
          lastUpdateSource: null
        }));
      }
    },

    clearUpdateSource() {
      update(state => ({
        ...state,
        lastUpdateSource: null
      }));
    },

    openPreview(title: string, content: string) {
      set({
        currentNoteId: 'prompt-preview',
        currentNotePath: null,
        currentNoteName: title,
        content,
        originalContent: content,
        isDirty: false,
        isSaving: false,
        isLoading: false,
        lastSaved: null,
        saveError: null,
        basePath: 'preview',
        isReadOnly: true,
        lastUpdateSource: null
      });
    },

    reset() {
      set({
        currentNoteId: null,
        currentNotePath: null,
        currentNoteName: null,
        content: '',
        originalContent: '',
        isDirty: false,
        isSaving: false,
        isLoading: false,
        lastSaved: null,
        saveError: null,
        basePath: 'notes',
        isReadOnly: false,
        lastUpdateSource: null
      });
    }
  };
}

export const editorStore = createEditorStore();
export type EditorStore = ReturnType<typeof createEditorStore>;
export const currentNoteId = writable<string | null>(null);
