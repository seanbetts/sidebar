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
    basePath: 'notes'
  });

  return {
    subscribe,

    async loadNote(basePath: string, path: string) {
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
          basePath
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
        isDirty: newContent !== state.originalContent
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
          saveError: null
        }));
      } catch (error) {
        update(s => ({
          ...s,
          isSaving: false,
          saveError: 'Failed to save note'
        }));
      }
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
        basePath: 'notes'
      });
    }
  };
}

export const editorStore = createEditorStore();
export const currentNoteId = writable<string | null>(null);
