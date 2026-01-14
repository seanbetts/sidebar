import { EditorState, Compartment, RangeSetBuilder } from '@codemirror/state';
import { Decoration, EditorView, keymap, ViewPlugin } from '@codemirror/view';
import { defaultKeymap, history, historyKeymap } from '@codemirror/commands';
import { HighlightStyle, indentOnInput, syntaxHighlighting } from '@codemirror/language';
import { markdown } from '@codemirror/lang-markdown';
import { GFM } from '@lezer/markdown';
import { tags } from '@lezer/highlight';

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
	{ tag: tags.heading1, fontWeight: '700' },
	{ tag: tags.heading2, fontWeight: '600' },
	{ tag: tags.heading3, fontWeight: '600' },
	{ tag: tags.heading4, fontWeight: '600' },
	{ tag: tags.heading5, fontWeight: '600' },
	{ tag: tags.heading6, fontWeight: '600' },
	{ tag: tags.strong, fontWeight: '700' },
	{ tag: tags.emphasis, fontStyle: 'italic' },
	{ tag: tags.strikethrough, textDecoration: 'line-through' },
	{
		tag: tags.monospace,
		fontFamily:
			'ui-monospace, "Cascadia Code", "Source Code Pro", Menlo, Consolas, "DejaVu Sans Mono", monospace',
		fontSize: '0.875em',
		backgroundColor: 'var(--color-muted)',
		borderRadius: '0.25em',
		padding: '0.2em 0.4em'
	},
	{ tag: tags.link, color: 'var(--color-primary)', textDecoration: 'underline' },
	{ tag: tags.url, color: 'var(--color-primary)', textDecoration: 'underline' },
	{ tag: tags.quote, color: 'var(--color-muted-foreground)' },
	{ tag: tags.contentSeparator, color: 'var(--color-border)' },
	{ tag: tags.separator, color: 'var(--color-border)' },
	{ tag: tags.meta, color: 'var(--color-muted-foreground)' }
]);

const blockquoteDecoration = Decoration.line({ class: 'cm-blockquote' });
const heading1Decoration = Decoration.line({ class: 'cm-heading cm-heading-1' });
const heading2Decoration = Decoration.line({ class: 'cm-heading cm-heading-2' });
const heading3Decoration = Decoration.line({ class: 'cm-heading cm-heading-3' });
const heading4Decoration = Decoration.line({ class: 'cm-heading cm-heading-4' });
const heading5Decoration = Decoration.line({ class: 'cm-heading cm-heading-5' });
const heading6Decoration = Decoration.line({ class: 'cm-heading cm-heading-6' });
const hrDecoration = Decoration.line({ class: 'cm-hr' });
const listDecoration = Decoration.line({ class: 'cm-list-item' });
const taskDecoration = Decoration.line({ class: 'cm-task-item' });
const taskCheckedDecoration = Decoration.line({ class: 'cm-task-item cm-task-item--checked' });
const codeBlockDecoration = Decoration.line({ class: 'cm-code-block' });
const codeBlockStartDecoration = Decoration.line({ class: 'cm-code-block cm-code-block--start' });
const codeBlockEndDecoration = Decoration.line({ class: 'cm-code-block cm-code-block--end' });
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
			const headingRegex = /^\s{0,3}(#{1,6})\s+/;
			const hrRegex = /^\s*(\*{3,}|-{3,}|_{3,})\s*$/;
			const listRegex = /^\s*(?:[-*+]|\d+\.)\s+/;
			const fenceRegex = /^(\s*)(`{3,}|~{3,})/;
			const tableSeparatorRegex = /^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$/;
			const tableRowRegex = /^\s*\|[^|]+\|[^|]+/;
			const taskRegex = /^\s*[-*+]\s+\[( |x|X)\]\s+/;

			for (const { from, to } of view.visibleRanges) {
				let pos = from;
				let pendingTableHeader = false;
				let inTable = false;
				let tableRowIndex = 0;
				let inFence = false;
				let fenceMarker = '';
				let fenceSize = 0;
				while (pos <= to) {
					const line = view.state.doc.lineAt(pos);
					const text = line.text;
					const fenceMatch = fenceRegex.exec(text);
					if (fenceMatch) {
						const marker = fenceMatch[2];
						if (!inFence) {
							inFence = true;
							fenceMarker = marker[0];
							fenceSize = marker.length;
							builder.add(line.from, line.from, codeBlockStartDecoration);
						} else if (marker[0] == fenceMarker && marker.length >= fenceSize) {
							inFence = false;
							builder.add(line.from, line.from, codeBlockEndDecoration);
						} else {
							builder.add(line.from, line.from, codeBlockDecoration);
						}
						pos = line.to + 1;
						continue;
					}

					if (inFence) {
						builder.add(line.from, line.from, codeBlockDecoration);
						pos = line.to + 1;
						continue;
					}

					const headingMatch = headingRegex.exec(text);
					const isBlockquote = /^\s*>\s?/.test(text);
					const taskMatch = taskRegex.exec(text);
					const isListItem = listRegex.test(text);
					const isHr = hrRegex.test(text);
					const isSeparator = tableSeparatorRegex.test(text);
					const isTableRow = tableRowRegex.test(text) && !isSeparator;

					if (headingMatch) {
						const level = headingMatch[1].length;
						switch (level) {
							case 1:
								builder.add(line.from, line.from, heading1Decoration);
								break;
							case 2:
								builder.add(line.from, line.from, heading2Decoration);
								break;
							case 3:
								builder.add(line.from, line.from, heading3Decoration);
								break;
							case 4:
								builder.add(line.from, line.from, heading4Decoration);
								break;
							case 5:
								builder.add(line.from, line.from, heading5Decoration);
								break;
							case 6:
								builder.add(line.from, line.from, heading6Decoration);
								break;
							default:
								break;
						}
					}

					if (isHr) {
						builder.add(line.from, line.from, hrDecoration);
					}

					if (isListItem || taskMatch) {
						builder.add(line.from, line.from, listDecoration);
					}

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
						inTable = true;
					}

					if (isTableRow && (inTable || pendingTableHeader)) {
						if (pendingTableHeader) {
							builder.add(line.from, line.from, tableHeaderDecoration);
							pendingTableHeader = false;
							inTable = true;
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
						inTable = false;
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

function initializeEditor() {
	const root = document.getElementById('editor');
	if (!root) {
		postToNative('jsError', { message: 'Missing editor root element' });
		return;
	}

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
}

if (document.readyState === 'loading') {
	document.addEventListener('DOMContentLoaded', initializeEditor, { once: true });
} else {
	initializeEditor();
}
