import { EditorState, Compartment } from '@codemirror/state';
import { EditorView, keymap } from '@codemirror/view';
import { defaultKeymap, history, historyKeymap } from '@codemirror/commands';
import { indentOnInput } from '@codemirror/language';
import { markdown } from '@codemirror/lang-markdown';

type WebKitMessageHandler = {
	postMessage: (payload: unknown) => void;
};

type WebKitBridge = {
	messageHandlers: Record<string, WebKitMessageHandler>;
};

type EditorAPI = {
	setMarkdown: (text: string) => void;
	getMarkdown: () => string;
	setReadOnly: (isReadOnly: boolean) => void;
	focus: () => void;
	applyCommand: (command: string, payload?: unknown) => boolean;
};

declare global {
	interface Window {
		editorAPI?: EditorAPI;
		webkit?: WebKitBridge;
	}
}

const root = document.getElementById('editor');

if (!root) {
	throw new Error('Missing editor root element');
}

const readOnlyCompartment = new Compartment();
let view: EditorView | null = null;
let suppressChangeEvent = false;
let debounceTimer: number | undefined;
const debounceMs = 250;

/** Post a message to the native WKWebView bridge if available. */
function postToNative(handlerName: string, payload: unknown) {
	const handler = window.webkit?.messageHandlers?.[handlerName];
	if (handler) {
		handler.postMessage(payload);
	}
}

/** Get the current markdown from the editor. */
function getMarkdown(): string {
	if (!view) return '';
	return view.state.doc.toString();
}

/** Replace the editor content with new markdown text. */
function setMarkdown(text: string) {
	if (!view) return;
	const current = view.state.doc.toString();
	if (current === text) return;
	suppressChangeEvent = true;
	view.dispatch({
		changes: { from: 0, to: current.length, insert: text }
	});
}

/** Update read-only state for the editor. */
function setReadOnly(isReadOnly: boolean) {
	if (!view) return;
	view.dispatch({
		effects: readOnlyCompartment.reconfigure([
			EditorState.readOnly.of(isReadOnly),
			EditorView.editable.of(!isReadOnly)
		])
	});
}

/** Focus the editor if mounted. */
function focus() {
	view?.focus();
}

/** Apply a command by name. Returns false when not supported. */
function applyCommand(_command: string, _payload?: unknown): boolean {
	return false;
}

const updateListener = EditorView.updateListener.of((update) => {
	if (!update.docChanged) return;
	if (suppressChangeEvent) {
		suppressChangeEvent = false;
		return;
	}
	if (debounceTimer) {
		window.clearTimeout(debounceTimer);
	}
	debounceTimer = window.setTimeout(() => {
		postToNative('contentChanged', { text: getMarkdown() });
	}, debounceMs);
});

const state = EditorState.create({
	doc: '',
	extensions: [
		readOnlyCompartment.of([EditorState.readOnly.of(false), EditorView.editable.of(true)]),
		history(),
		indentOnInput(),
		markdown(),
		keymap.of([...defaultKeymap, ...historyKeymap]),
		EditorView.lineWrapping,
		updateListener
	]
});

view = new EditorView({
	state,
	parent: root
});

window.editorAPI = {
	setMarkdown,
	getMarkdown,
	setReadOnly,
	focus,
	applyCommand
};

postToNative('editorReady', {});
