import { EditorState, Compartment, RangeSetBuilder } from '@codemirror/state';
import { Decoration, EditorView, keymap, ViewPlugin } from '@codemirror/view';
import { defaultKeymap, history, historyKeymap } from '@codemirror/commands';
import { indentOnInput, syntaxHighlighting } from '@codemirror/language';
import { markdown } from '@codemirror/lang-markdown';
import { HighlightStyle, tags } from '@codemirror/highlight';
import { GFM } from '@lezer/markdown';

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

const editorTheme = EditorView.theme(
	{
		'&': {
			backgroundColor: 'var(--color-background)',
			color: 'var(--color-foreground)'
		},
		'.cm-content': {
			fontFamily:
				'-apple-system, BlinkMacSystemFont, "Segoe UI", ui-sans-serif, system-ui, sans-serif',
			lineHeight: '1.7'
		},
		'.cm-content .cm-line': {
			padding: '0.15em 0'
		},
		'.cm-gutters': {
			backgroundColor: 'var(--color-muted)',
			color: 'var(--color-muted-foreground)',
			borderRight: '1px solid var(--color-border)'
		},
		'.cm-blockquote': {
			borderLeft: '3px solid var(--color-border)',
			paddingLeft: '1em',
			color: 'var(--color-muted-foreground)'
		},
		'.cm-cursor, .cm-dropCursor': {
			borderLeftColor: 'var(--color-foreground)'
		},
		'&.cm-focused .cm-selectionBackground, ::selection': {
			backgroundColor: 'color-mix(in oklab, var(--color-primary) 30%, transparent)'
		},
		'.cm-activeLine': {
			backgroundColor: 'color-mix(in oklab, var(--color-muted) 60%, transparent)'
		}
	},
	{ dark: false }
);

const editorThemeDark = EditorView.theme(
	{
		'&': {
			backgroundColor: 'var(--color-background)',
			color: 'var(--color-foreground)'
		},
		'.cm-gutters': {
			backgroundColor: 'var(--color-muted)',
			color: 'var(--color-muted-foreground)',
			borderRight: '1px solid var(--color-border)'
		},
		'.cm-blockquote': {
			borderLeft: '3px solid var(--color-border)',
			paddingLeft: '1em',
			color: 'var(--color-muted-foreground)'
		},
		'.cm-cursor, .cm-dropCursor': {
			borderLeftColor: 'var(--color-foreground)'
		},
		'&.cm-focused .cm-selectionBackground, ::selection': {
			backgroundColor: 'color-mix(in oklab, var(--color-primary) 30%, transparent)'
		},
		'.cm-activeLine': {
			backgroundColor: 'color-mix(in oklab, var(--color-muted) 50%, transparent)'
		}
	},
	{ dark: true }
);

const highlightStyle = HighlightStyle.define([
	{ tag: tags.heading1, fontWeight: '700', fontSize: '2em' },
	{ tag: tags.heading2, fontWeight: '600', fontSize: '1.5em' },
	{ tag: tags.heading3, fontWeight: '600', fontSize: '1.25em' },
	{ tag: tags.strong, fontWeight: '700' },
	{ tag: tags.emphasis, fontStyle: 'italic' },
	{ tag: tags.strikethrough, textDecoration: 'line-through' },
	{
		tag: tags.code,
		fontFamily:
			'ui-monospace, "Cascadia Code", "Source Code Pro", Menlo, Consolas, "DejaVu Sans Mono", monospace',
		fontSize: '0.875em',
		backgroundColor: 'var(--color-muted)',
		borderRadius: '0.25em',
		padding: '0.15em 0.35em'
	},
	{ tag: tags.listMark, color: 'var(--color-muted-foreground)' },
	{ tag: tags.list, color: 'var(--color-foreground)' },
	{ tag: tags.link, color: 'var(--color-primary)', textDecoration: 'underline' },
	{ tag: tags.url, color: 'var(--color-primary)', textDecoration: 'underline' },
	{ tag: tags.quote, color: 'var(--color-muted-foreground)' },
	{ tag: tags.contentSeparator, color: 'var(--color-border)' },
	{ tag: tags.separator, color: 'var(--color-border)' },
	{ tag: tags.meta, color: 'var(--color-muted-foreground)' }
]);

const blockquoteDecoration = Decoration.line({ class: 'cm-blockquote' });

const blockquotePlugin = ViewPlugin.fromClass(
	class {
		decorations = Decoration.none;

		constructor(view: EditorView) {
			this.decorations = this.buildDecorations(view);
		}

		update(update: { docChanged: boolean; viewportChanged: boolean; view: EditorView }) {
			if (update.docChanged || update.viewportChanged) {
				this.decorations = this.buildDecorations(update.view);
			}
		}

		private buildDecorations(view: EditorView) {
			const builder = new RangeSetBuilder<Decoration>();
			for (const { from, to } of view.visibleRanges) {
				let pos = from;
				while (pos <= to) {
					const line = view.state.doc.lineAt(pos);
					if (/^\s*>\s?/.test(line.text)) {
						builder.add(line.from, line.from, blockquoteDecoration);
					}
					pos = line.to + 1;
				}
			}
			return builder.finish();
		}
	},
	{
		decorations: (value) => value.decorations
	}
);

const state = EditorState.create({
	doc: '',
	extensions: [
		editorTheme,
		editorThemeDark,
		syntaxHighlighting(highlightStyle),
		readOnlyCompartment.of([EditorState.readOnly.of(false), EditorView.editable.of(true)]),
		history(),
		indentOnInput(),
		markdown({ extensions: [GFM] }),
		keymap.of([...defaultKeymap, ...historyKeymap]),
		EditorView.lineWrapping,
		blockquotePlugin,
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
