import { EditorState, Compartment, RangeSetBuilder } from '@codemirror/state';
import { Decoration, EditorView, keymap, ViewPlugin, WidgetType } from '@codemirror/view';
import { defaultKeymap, history, historyKeymap } from '@codemirror/commands';
import { HighlightStyle, indentOnInput, syntaxHighlighting } from '@codemirror/language';
import { markdown } from '@codemirror/lang-markdown';
import { Autolink, GFM } from '@lezer/markdown';
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
const taskToggleRegex = /^(\s*[-*+]\s+)\[( |x|X)\](\s+)/;
const lightCaretColor = '#6b6b6b';
const darkCaretColor = '#c9c9c9';
const markdownLinkRegex = /\[([^\]]+)\]\(([^)\s]+)(?:\s+["'][^"']*["'])?\)/g;
const angleLinkRegex = /<((?:https?:\/\/|mailto:)[^>\s]+)>/g;
const bareUrlRegex = /(?:https?:\/\/|www\.)[^\s)]+/g;
const emailRegex = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g;
const headingRegex = /^(\s*)(#{1,6})\s+/;
const bulletListRegex = /^(\s*)([-*+])\s+/;
const orderedListRegex = /^(\s*)(\d+)\.\s+/;
const taskListRegex = /^(\s*)([-*+])\s+\[( |x|X)\]\s+/;
const blockquoteRegex = /^(\s*)>\s+/;

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

function getSelection() {
	if (!view) return null;
	return view.state.selection.main;
}

function dispatchChanges(
	changes: { from: number; to: number; insert: string }[],
	selection?: { anchor: number; head: number }
) {
	if (!view) return;
	view.dispatch({
		changes,
		selection,
		scrollIntoView: true,
		userEvent: 'input'
	});
}

function toggleInlineWrap(prefix: string, suffix: string, placeholder: string) {
	const selection = getSelection();
	if (!selection || !view) return false;
	const doc = view.state.doc;
	const from = selection.from;
	const to = selection.to;
	const selected = doc.sliceString(from, to);
	if (selection.empty) {
		const insert = `${prefix}${placeholder}${suffix}`;
		dispatchChanges([{ from, to, insert }], {
			anchor: from + prefix.length,
			head: from + prefix.length + placeholder.length
		});
		return true;
	}
	if (selected.startsWith(prefix) && selected.endsWith(suffix)) {
		const stripped = selected.slice(prefix.length, selected.length - suffix.length);
		dispatchChanges([{ from, to, insert: stripped }], {
			anchor: from,
			head: from + stripped.length
		});
		return true;
	}
	dispatchChanges([{ from, to, insert: `${prefix}${selected}${suffix}` }], {
		anchor: from + prefix.length,
		head: to + prefix.length
	});
	return true;
}

function getLinesInRange(from: number, to: number) {
	if (!view) return [];
	const lines = [];
	let pos = from;
	while (pos <= to) {
		const line = view.state.doc.lineAt(pos);
		lines.push(line);
		if (line.to >= to) break;
		pos = line.to + 1;
	}
	return lines;
}

function toggleLinePrefix(prefix: string, removeRegex: RegExp) {
	const selection = getSelection();
	if (!selection || !view) return false;
	const lines = getLinesInRange(selection.from, selection.to);
	const changes: { from: number; to: number; insert: string }[] = [];
	for (let index = lines.length - 1; index >= 0; index -= 1) {
		const line = lines[index];
		const match = removeRegex.exec(line.text);
		if (match) {
			const start = line.from + match[1].length;
			const end = line.from + match[0].length;
			changes.push({ from: start, to: end, insert: '' });
		} else {
			const indent = /^(\s*)/.exec(line.text)?.[1] ?? '';
			const insertAt = line.from + indent.length;
			changes.push({ from: insertAt, to: insertAt, insert: prefix });
		}
	}
	if (changes.length) {
		dispatchChanges(changes);
		return true;
	}
	return false;
}

function toggleHeading(level: number) {
	const selection = getSelection();
	if (!selection || !view) return false;
	const prefix = `${'#'.repeat(level)} `;
	const lines = getLinesInRange(selection.from, selection.to);
	const changes: { from: number; to: number; insert: string }[] = [];
	for (let index = lines.length - 1; index >= 0; index -= 1) {
		const line = lines[index];
		const match = headingRegex.exec(line.text);
		if (match && match[2].length === level) {
			const start = line.from + match[1].length;
			const end = line.from + match[0].length;
			changes.push({ from: start, to: end, insert: '' });
		} else if (match) {
			const start = line.from + match[1].length;
			const end = line.from + match[0].length;
			changes.push({ from: start, to: end, insert: prefix });
		} else {
			const indent = /^(\s*)/.exec(line.text)?.[1] ?? '';
			const insertAt = line.from + indent.length;
			changes.push({ from: insertAt, to: insertAt, insert: prefix });
		}
	}
	if (changes.length) {
		dispatchChanges(changes);
		return true;
	}
	return false;
}

function toggleBulletList() {
	return toggleLinePrefix('- ', bulletListRegex);
}

function toggleOrderedList() {
	const selection = getSelection();
	if (!selection || !view) return false;
	const lines = getLinesInRange(selection.from, selection.to);
	const changes: { from: number; to: number; insert: string }[] = [];
	for (let index = lines.length - 1; index >= 0; index -= 1) {
		const line = lines[index];
		const match = orderedListRegex.exec(line.text);
		if (match) {
			const start = line.from + match[1].length;
			const end = line.from + match[0].length;
			changes.push({ from: start, to: end, insert: '' });
		} else {
			const indent = /^(\s*)/.exec(line.text)?.[1] ?? '';
			const insertAt = line.from + indent.length;
			changes.push({ from: insertAt, to: insertAt, insert: '1. ' });
		}
	}
	if (changes.length) {
		dispatchChanges(changes);
		return true;
	}
	return false;
}

function toggleTaskList() {
	const selection = getSelection();
	if (!selection || !view) return false;
	const lines = getLinesInRange(selection.from, selection.to);
	const changes: { from: number; to: number; insert: string }[] = [];
	for (let index = lines.length - 1; index >= 0; index -= 1) {
		const line = lines[index];
		const match = taskListRegex.exec(line.text);
		if (match) {
			const start = line.from + match[1].length;
			const end = line.from + match[0].length;
			changes.push({ from: start, to: end, insert: '' });
			continue;
		}
		const bulletMatch = bulletListRegex.exec(line.text);
		if (bulletMatch) {
			const start = line.from + bulletMatch[1].length;
			const end = line.from + bulletMatch[0].length;
			changes.push({ from: start, to: end, insert: '- [ ] ' });
			continue;
		}
		const indent = /^(\s*)/.exec(line.text)?.[1] ?? '';
		const insertAt = line.from + indent.length;
		changes.push({ from: insertAt, to: insertAt, insert: '- [ ] ' });
	}
	if (changes.length) {
		dispatchChanges(changes);
		return true;
	}
	return false;
}

function toggleBlockquote() {
	return toggleLinePrefix('> ', blockquoteRegex);
}

function insertHorizontalRule() {
	const selection = getSelection();
	if (!selection || !view) return false;
	dispatchChanges([{ from: selection.from, to: selection.to, insert: '\n---\n' }]);
	return true;
}

function insertLink() {
	const selection = getSelection();
	if (!selection || !view) return false;
	const doc = view.state.doc;
	const from = selection.from;
	const to = selection.to;
	const selected = doc.sliceString(from, to);
	const label = selected || 'link';
	const url = 'https://';
	const insert = `[${label}](${url})`;
	const urlStart = from + label.length + 3;
	dispatchChanges([{ from, to, insert }], { anchor: urlStart, head: urlStart + url.length });
	return true;
}

function insertCodeBlock() {
	const selection = getSelection();
	if (!selection || !view) return false;
	const doc = view.state.doc;
	const from = selection.from;
	const to = selection.to;
	const selected = doc.sliceString(from, to);
	if (selected) {
		const insert = `\n\`\`\`\n${selected}\n\`\`\`\n`;
		dispatchChanges([{ from, to, insert }], {
			anchor: from + 5,
			head: from + 5 + selected.length
		});
		return true;
	}
	const insert = '\n```\n\n```\n';
	const cursor = from + 5;
	dispatchChanges([{ from, to, insert }], { anchor: cursor, head: cursor });
	return true;
}

function insertTable() {
	const selection = getSelection();
	if (!selection || !view) return false;
	const from = selection.from;
	const to = selection.to;
	const insert = '\n| Header | Header |\n| --- | --- |\n| Cell | Cell |\n';
	const headerStart = from + 3;
	dispatchChanges([{ from, to, insert }], { anchor: headerStart, head: headerStart + 6 });
	return true;
}

function applyCommand(command: string, _payload?: unknown): boolean {
	if (!view) return false;
	if (view.state.facet(EditorState.readOnly)) return false;
	switch (command) {
		case 'bold':
			return toggleInlineWrap('**', '**', 'bold');
		case 'italic':
			return toggleInlineWrap('*', '*', 'italic');
		case 'strike':
			return toggleInlineWrap('~~', '~~', 'strike');
		case 'inlineCode':
			return toggleInlineWrap('`', '`', 'code');
		case 'heading1':
			return toggleHeading(1);
		case 'heading2':
			return toggleHeading(2);
		case 'heading3':
			return toggleHeading(3);
		case 'bulletList':
			return toggleBulletList();
		case 'orderedList':
			return toggleOrderedList();
		case 'taskList':
			return toggleTaskList();
		case 'blockquote':
			return toggleBlockquote();
		case 'hr':
			return insertHorizontalRule();
		case 'link':
			return insertLink();
		case 'codeBlock':
			return insertCodeBlock();
		case 'table':
			return insertTable();
		default:
			return false;
	}
}

const formattingKeymap = keymap.of([
	{ key: 'Mod-b', run: () => applyCommand('bold') },
	{ key: 'Mod-i', run: () => applyCommand('italic') },
	{ key: 'Mod-Shift-x', run: () => applyCommand('strike') },
	{ key: 'Mod-`', run: () => applyCommand('inlineCode') },
	{ key: 'Mod-Alt-1', run: () => applyCommand('heading1') },
	{ key: 'Mod-Alt-2', run: () => applyCommand('heading2') },
	{ key: 'Mod-Alt-3', run: () => applyCommand('heading3') },
	{ key: 'Mod-Shift-7', run: () => applyCommand('orderedList') },
	{ key: 'Mod-Shift-8', run: () => applyCommand('bulletList') },
	{ key: 'Mod-Shift-9', run: () => applyCommand('blockquote') },
	{ key: 'Mod-Shift-k', run: () => applyCommand('link') }
]);

function applyCaretOverride() {
	const prefersDark = window.matchMedia?.('(prefers-color-scheme: dark)').matches ?? false;
	const caretColor = prefersDark ? darkCaretColor : lightCaretColor;
	document.documentElement.style.setProperty('--color-caret', caretColor);
	const styleId = 'cm-caret-override';
	let styleEl = document.getElementById(styleId) as HTMLStyleElement | null;
	if (!styleEl) {
		styleEl = document.createElement('style');
		styleEl.id = styleId;
		document.head.appendChild(styleEl);
	}
	styleEl.textContent = `
		.cm-content { caret-color: ${caretColor} !important; }
		.cm-editor .cm-cursor,
		.cm-editor .cm-dropCursor { border-left: 2px solid ${caretColor} !important; }
	`;
}

function findLinkAt(text: string, offset: number): string | null {
	const findMatch = (regex: RegExp, extractor: (match: RegExpExecArray) => string) => {
		regex.lastIndex = 0;
		let match = regex.exec(text);
		while (match) {
			const start = match.index;
			const end = start + match[0].length;
			if (offset >= start && offset <= end) {
				return extractor(match);
			}
			match = regex.exec(text);
		}
		return null;
	};

	return (
		findMatch(markdownLinkRegex, (match) => match[2]) ??
		findMatch(angleLinkRegex, (match) => match[1]) ??
		findMatch(bareUrlRegex, (match) => match[0]) ??
		findMatch(emailRegex, (match) => `mailto:${match[0]}`)
	);
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

const taskToggleHandler = EditorView.domEventHandlers({
	mousedown: (event, view) => {
		if (event.button !== 0) return false;
		if (view.state.facet(EditorState.readOnly)) return false;
		const coords = { x: event.clientX, y: event.clientY };
		const pos = view.posAtCoords(coords);
		if (pos == null) return false;
		const line = view.state.doc.lineAt(pos);
		const match = taskToggleRegex.exec(line.text);
		if (!match) return false;
		const lineStart = view.coordsAtPos(line.from);
		if (lineStart && event.clientX > lineStart.left + 24) return false;
		const statePos = line.from + match[1].length + 1;
		const nextState = match[2].toLowerCase() === 'x' ? ' ' : 'x';
		view.dispatch({
			changes: { from: statePos, to: statePos + 1, insert: nextState }
		});
		view.focus();
		event.preventDefault();
		return true;
	}
});

const linkClickHandler = EditorView.domEventHandlers({
	click: (event, view) => {
		if (event.defaultPrevented) return false;
		const isReadOnly = view.state.facet(EditorState.readOnly);
		if (!isReadOnly && !event.metaKey && !event.ctrlKey) return false;
		const pos = view.posAtCoords({ x: event.clientX, y: event.clientY });
		if (pos == null) return false;
		const line = view.state.doc.lineAt(pos);
		const offset = pos - line.from;
		const href = findLinkAt(line.text, offset);
		if (!href) return false;
		const resolvedHref = href.startsWith('www.') ? `https://${href}` : href;
		postToNative('linkTapped', { href: resolvedHref });
		event.preventDefault();
		return true;
	}
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
		'.cm-gutters': {
			backgroundColor: 'var(--color-muted)',
			color: 'var(--color-muted-foreground)',
			borderRight: '1px solid var(--color-border)'
		},
		'.cm-cursor, .cm-dropCursor': {
			borderLeftColor: 'var(--color-caret)'
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
			borderLeftColor: 'var(--color-caret)'
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
		fontFamily: '"SF Mono", Monaco, "Cascadia Code", "Courier New", monospace',
		fontSize: '0.875em',
		color: 'var(--color-foreground)',
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

type ImageWidgetConfig = {
	src: string;
	alt: string;
	title: string;
};

class ImageWidget extends WidgetType {
	constructor(private config: ImageWidgetConfig) {
		super();
	}

	eq(other: ImageWidget) {
		return (
			this.config.src === other.config.src &&
			this.config.alt === other.config.alt &&
			this.config.title === other.config.title
		);
	}

	toDOM() {
		const figure = document.createElement('figure');
		figure.className = 'cm-media-widget';

		const image = document.createElement('img');
		image.src = this.config.src;
		image.alt = this.config.alt;
		image.loading = 'lazy';
		image.decoding = 'async';
		figure.appendChild(image);

		if (this.config.title) {
			const caption = document.createElement('figcaption');
			caption.textContent = this.config.title;
			figure.appendChild(caption);
		}

		return figure;
	}
}

const blockquoteDecoration = Decoration.line({ class: 'cm-blockquote' });
const blockquoteStartDecoration = Decoration.line({ class: 'cm-blockquote cm-blockquote-start' });
const blockquoteEndDecoration = Decoration.line({ class: 'cm-blockquote cm-blockquote-end' });
const heading1Decoration = Decoration.line({ class: 'cm-heading cm-heading-1' });
const heading2Decoration = Decoration.line({ class: 'cm-heading cm-heading-2' });
const heading3Decoration = Decoration.line({ class: 'cm-heading cm-heading-3' });
const heading4Decoration = Decoration.line({ class: 'cm-heading cm-heading-4' });
const heading5Decoration = Decoration.line({ class: 'cm-heading cm-heading-5' });
const heading6Decoration = Decoration.line({ class: 'cm-heading cm-heading-6' });
const paragraphDecoration = Decoration.line({ class: 'cm-paragraph' });
const hrDecoration = Decoration.line({ class: 'cm-hr' });
const listDecoration = Decoration.line({ class: 'cm-list-item' });
const listStartDecoration = Decoration.line({ class: 'cm-list-item cm-list-start' });
const listEndDecoration = Decoration.line({ class: 'cm-list-item cm-list-end' });
const listNestedDecoration = Decoration.line({ class: 'cm-list-item cm-list-nested' });
const orderedListDecoration = Decoration.line({ class: 'cm-list-item cm-list-ordered' });
const unorderedListDecoration = Decoration.line({ class: 'cm-list-item cm-list-unordered' });
const taskDecoration = Decoration.line({ class: 'cm-task-item' });
const taskCheckedDecoration = Decoration.line({ class: 'cm-task-item cm-task-item--checked' });
const codeBlockDecoration = Decoration.line({ class: 'cm-code-block' });
const codeBlockStartDecoration = Decoration.line({ class: 'cm-code-block cm-code-block--start' });
const codeBlockEndDecoration = Decoration.line({ class: 'cm-code-block cm-code-block--end' });
const mediaDecoration = Decoration.line({ class: 'cm-media-line' });
const blankLineDecoration = Decoration.line({ class: 'cm-blank-line' });
const tableRowDecoration = Decoration.line({ class: 'cm-table-row' });
const tableRowEvenDecoration = Decoration.line({ class: 'cm-table-row cm-table-row--even' });
const tableHeaderDecoration = Decoration.line({ class: 'cm-table-row cm-table-header' });
const tableSeparatorDecoration = Decoration.line({ class: 'cm-table-separator' });
const tableStartDecoration = Decoration.line({ class: 'cm-table-start' });
const tableEndDecoration = Decoration.line({ class: 'cm-table-end' });

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
			const listRegex = /^(\s*)((?:[-*+])|(?:\d+\.))\s+/;
			const fenceRegex = /^(\s*)(`{3,}|~{3,})/;
			const imageRegex = /^\s*!\[([^\]]*)]\(([^)\s]+)(?:\s+["']([^"']*)["'])?\)\s*$/;
			const tableSeparatorRegex = /^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$/;
			const tableRowRegex = /^\s*\|?[^|]+\|[^|]+(?:\|[^|]+)*\|?\s*$/;
			const taskRegex = /^\s*[-*+]\s+\[( |x|X)\]\s+/;

			for (const { from, to } of view.visibleRanges) {
				let pos = from;
				let pendingTableHeader = false;
				let inTable = false;
				let tableRowIndex = 0;
				let lastTableRowFrom: number | null = null;
				let inFence = false;
				let fenceMarker = '';
				let fenceSize = 0;
				let inBlockquote = false;
				let lastBlockquoteLineFrom: number | null = null;
				let inList = false;
				let lastListLineFrom: number | null = null;
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
					const listMatch = listRegex.exec(text);
					const isBlockquote = /^\s*>\s?/.test(text);
					const taskMatch = taskRegex.exec(text);
					const isListItem = listMatch != null;
					const isHr = hrRegex.test(text);
					const imageMatch = imageRegex.exec(text);
					const isImage = imageMatch != null;
					const isBlank = /^\s*$/.test(text);
					const isSeparator = tableSeparatorRegex.test(text);
					const isTableRow = tableRowRegex.test(text) && !isSeparator;

					if (isBlockquote) {
						if (!inBlockquote) {
							builder.add(line.from, line.from, blockquoteStartDecoration);
							inBlockquote = true;
						} else {
							builder.add(line.from, line.from, blockquoteDecoration);
						}
						lastBlockquoteLineFrom = line.from;
					} else if (inBlockquote) {
						if (lastBlockquoteLineFrom != null) {
							builder.add(lastBlockquoteLineFrom, lastBlockquoteLineFrom, blockquoteEndDecoration);
						}
						inBlockquote = false;
						lastBlockquoteLineFrom = null;
					}

					if (isListItem || taskMatch) {
						const indent = listMatch ? listMatch[1].length : 0;
						const marker = listMatch ? listMatch[2] : '';
						if (marker && marker.endsWith('.')) {
							builder.add(line.from, line.from, orderedListDecoration);
						} else if (marker) {
							builder.add(line.from, line.from, unorderedListDecoration);
						}
						if (indent > 0) {
							builder.add(line.from, line.from, listNestedDecoration);
						} else if (!inList) {
							builder.add(line.from, line.from, listStartDecoration);
							inList = true;
							lastListLineFrom = line.from;
						} else {
							builder.add(line.from, line.from, listDecoration);
							lastListLineFrom = line.from;
						}
					} else if (inList) {
						if (lastListLineFrom != null) {
							builder.add(lastListLineFrom, lastListLineFrom, listEndDecoration);
						}
						inList = false;
						lastListLineFrom = null;
					}

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

					if (isImage && imageMatch) {
						builder.add(line.from, line.from, mediaDecoration);
						const [, alt, src, title] = imageMatch;
						builder.add(
							line.to,
							line.to,
							Decoration.widget({
								widget: new ImageWidget({ src, alt, title: title ?? '' }),
								block: true,
								side: 1
							})
						);
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
						if (lastTableRowFrom == null) {
							builder.add(line.from, line.from, tableStartDecoration);
						}
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
						lastTableRowFrom = line.from;
					} else if (!isSeparator) {
						if (lastTableRowFrom != null) {
							builder.add(lastTableRowFrom, lastTableRowFrom, tableEndDecoration);
						}
						lastTableRowFrom = null;
						tableRowIndex = 0;
						pendingTableHeader = false;
						inTable = false;
					}

					if (taskMatch) {
						const isChecked = taskMatch[1].toLowerCase() == 'x';
						builder.add(line.from, line.from, isChecked ? taskCheckedDecoration : taskDecoration);
					}

					if (isBlank) {
						builder.add(line.from, line.from, blankLineDecoration);
					}

					if (
						!isBlank &&
						!headingMatch &&
						!isBlockquote &&
						!isListItem &&
						!taskMatch &&
						!isHr &&
						!isSeparator &&
						!isTableRow
					) {
						builder.add(line.from, line.from, paragraphDecoration);
					}

					pos = line.to + 1;
				}
				if (inBlockquote && lastBlockquoteLineFrom != null) {
					builder.add(lastBlockquoteLineFrom, lastBlockquoteLineFrom, blockquoteEndDecoration);
				}
				if (inList && lastListLineFrom != null) {
					builder.add(lastListLineFrom, lastListLineFrom, listEndDecoration);
				}
				if (inTable && lastTableRowFrom != null) {
					builder.add(lastTableRowFrom, lastTableRowFrom, tableEndDecoration);
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
	applyCaretOverride();

	const state = EditorState.create({
		doc: '',
		extensions: [
			editorTheme,
			editorThemeDark,
			syntaxHighlighting(highlightStyle),
			readOnlyCompartment.of([EditorState.readOnly.of(false), EditorView.editable.of(true)]),
			history(),
			indentOnInput(),
			markdown({ extensions: [GFM, Autolink], addKeymap: true }),
			keymap.of([...defaultKeymap, ...historyKeymap]),
			formattingKeymap,
			EditorView.lineWrapping,
			markdownLinePlugin,
			taskToggleHandler,
			linkClickHandler,
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
