import { writable, get } from 'svelte/store';

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
        const response = await fetch(
          `/api/files/content?basePath=${basePath}&path=${encodeURIComponent(path)}`
        );

        if (!response.ok) throw new Error('Failed to load note');

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
          lastUpdateSource: options?.source ?? null
        }));
      } catch (error) {
        update(state => ({
          ...state,
          isLoading: false,
          saveError: 'Failed to load note'
        }));
      }
    },

    updateContent(newContent: string) {
      update(state => ({
        ...state,
        content: newContent,
        isDirty: newContent !== state.originalContent,
        lastUpdateSource: null
      }));
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

      if (!state.currentNoteId || !state.isDirty) return;

      update(s => ({ ...s, isSaving: true, saveError: null }));

      try {
        const response = await fetch('/api/files/content', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            basePath: state.basePath,
            path: state.currentNoteId,
            content: state.content
          })
        });

        if (!response.ok) throw new Error('Failed to save note');

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
        lastUpdateSource: null
      });
    }
  };
}

export const editorStore = createEditorStore();
export const currentNoteId = writable<string | null>(null);
