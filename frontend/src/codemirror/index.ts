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
		'.cm-task-item': {
			paddingLeft: '2em',
			position: 'relative'
		},
		'.cm-task-item::before': {
			content: '""',
			position: 'absolute',
			left: '0.2em',
			top: '0.35em',
			width: '0.9em',
			height: '0.9em',
			border: '1px solid var(--color-border)',
			borderRadius: '0.2em',
			backgroundColor: 'var(--color-background)'
		},
		'.cm-task-item--checked': {
			color: 'var(--color-muted-foreground)',
			textDecoration: 'line-through'
		},
		'.cm-task-item--checked::before': {
			backgroundColor: 'var(--color-muted)',
			borderColor: 'var(--color-border)'
		},
		'.cm-task-item--checked::after': {
			content: '"x"',
			position: 'absolute',
			left: '0.45em',
			top: '0.18em',
			fontSize: '0.9em',
			color: 'var(--color-muted-foreground)'
		},
		'.cm-line.cm-table-row': {
			boxShadow:
				'inset 0 -1px 0 var(--color-border), inset 1px 0 0 var(--color-border), inset -1px 0 0 var(--color-border)',
			fontSize: '0.95em',
			padding: '0.35em 0.75em'
		},
		'.cm-line.cm-table-row--even': {
			backgroundColor: 'color-mix(in oklab, var(--color-muted) 40%, transparent)'
		},
		'.cm-line.cm-table-header': {
			backgroundColor: 'color-mix(in oklab, var(--color-foreground) 8%, transparent)',
			fontWeight: '600',
			boxShadow:
				'inset 0 -2px 0 var(--color-border), inset 1px 0 0 var(--color-border), inset -1px 0 0 var(--color-border)'
		},
		'.cm-line.cm-table-separator': {
			color: 'var(--color-border)'
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
		'.cm-task-item': {
			paddingLeft: '2em',
			position: 'relative'
		},
		'.cm-task-item::before': {
			content: '""',
			position: 'absolute',
			left: '0.2em',
			top: '0.35em',
			width: '0.9em',
			height: '0.9em',
			border: '1px solid var(--color-border)',
			borderRadius: '0.2em',
			backgroundColor: 'var(--color-background)'
		},
		'.cm-task-item--checked': {
			color: 'var(--color-muted-foreground)',
			textDecoration: 'line-through'
		},
		'.cm-task-item--checked::before': {
			backgroundColor: 'var(--color-muted)',
			borderColor: 'var(--color-border)'
		},
		'.cm-task-item--checked::after': {
			content: '"x"',
			position: 'absolute',
			left: '0.45em',
			top: '0.18em',
			fontSize: '0.9em',
			color: 'var(--color-muted-foreground)'
		},
		'.cm-line.cm-table-row': {
			boxShadow:
				'inset 0 -1px 0 var(--color-border), inset 1px 0 0 var(--color-border), inset -1px 0 0 var(--color-border)',
			fontSize: '0.95em',
			padding: '0.35em 0.75em'
		},
		'.cm-line.cm-table-row--even': {
			backgroundColor: 'color-mix(in oklab, var(--color-muted) 40%, transparent)'
		},
		'.cm-line.cm-table-header': {
			backgroundColor: 'color-mix(in oklab, var(--color-foreground) 8%, transparent)',
			fontWeight: '600',
			boxShadow:
				'inset 0 -2px 0 var(--color-border), inset 1px 0 0 var(--color-border), inset -1px 0 0 var(--color-border)'
		},
		'.cm-line.cm-table-separator': {
			color: 'var(--color-border)'
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
const taskDecoration = Decoration.line({ class: 'cm-task-item' });
const taskCheckedDecoration = Decoration.line({ class: 'cm-task-item cm-task-item--checked' });
const tableRowDecoration = Decoration.line({ class: 'cm-table-row' });
const tableRowEvenDecoration = Decoration.line({ class: 'cm-table-row cm-table-row--even' });
const tableHeaderDecoration = Decoration.line({ class: 'cm-table-row cm-table-header' });
const tableSeparatorDecoration = Decoration.line({ class: 'cm-table-separator' });

const markdownLinePlugin = ViewPlugin.fromClass(
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
			const tableSeparatorRegex = /^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$/;
			const tableRowRegex = /^\s*\|?.+\|.+/;
			const taskRegex = /^\s*[-*+]\s+\[( |x|X)\]\s+/;

			for (const { from, to } of view.visibleRanges) {
				let pos = from;
				let pendingTableHeader = false;
				let tableRowIndex = 0;
				while (pos <= to) {
					const line = view.state.doc.lineAt(pos);
					const text = line.text;
					const isBlockquote = /^\s*>\s?/.test(text);
					const taskMatch = taskRegex.exec(text);
					const isSeparator = tableSeparatorRegex.test(text);
					const isTableRow = tableRowRegex.test(text) && !isSeparator;

					if (isTableRow) {
						const nextPos = line.to + 1;
						if (nextPos <= to) {
							const nextLine = view.state.doc.lineAt(nextPos);
							if (tableSeparatorRegex.test(nextLine.text)) {
								pendingTableHeader = true;
							}
						}
					}

					if (isSeparator) {
						builder.add(line.from, line.from, tableSeparatorDecoration);
					}

					if (isTableRow) {
						if (pendingTableHeader) {
							builder.add(line.from, line.from, tableHeaderDecoration);
							pendingTableHeader = false;
							tableRowIndex = 0;
						} else {
							const decoration =
								tableRowIndex % 2 === 1 ? tableRowEvenDecoration : tableRowDecoration;
							builder.add(line.from, line.from, decoration);
							tableRowIndex += 1;
						}
					} else if (!isSeparator) {
						tableRowIndex = 0;
						pendingTableHeader = false;
					}

					if (isBlockquote) {
						builder.add(line.from, line.from, blockquoteDecoration);
					}

					if (taskMatch) {
						const isChecked = taskMatch[1].toLowerCase() == 'x';
						builder.add(line.from, line.from, isChecked ? taskCheckedDecoration : taskDecoration);
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
		markdownLinePlugin,
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
