import { EditorState, Compartment, RangeSetBuilder, Transaction } from '@codemirror/state';
import { Decoration, EditorView, keymap, ViewPlugin, WidgetType } from '@codemirror/view';
import { defaultKeymap, history, historyKeymap } from '@codemirror/commands';
import {
	HighlightStyle,
	LanguageDescription,
	indentOnInput,
	syntaxHighlighting,
	syntaxTree
} from '@codemirror/language';
import { markdown } from '@codemirror/lang-markdown';
import { javascript } from '@codemirror/lang-javascript';
import { json } from '@codemirror/lang-json';
import { html } from '@codemirror/lang-html';
import { css } from '@codemirror/lang-css';
import { python } from '@codemirror/lang-python';
import { sql } from '@codemirror/lang-sql';
import { yaml } from '@codemirror/lang-yaml';
import { xml } from '@codemirror/lang-xml';
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
const codeLanguages = [
	LanguageDescription.of({
		name: 'JavaScript',
		alias: ['js', 'jsx', 'ts', 'tsx', 'typescript'],
		support: javascript({ typescript: true, jsx: true })
	}),
	LanguageDescription.of({
		name: 'JSON',
		alias: ['jsonc'],
		support: json()
	}),
	LanguageDescription.of({
		name: 'HTML',
		alias: ['htm'],
		support: html()
	}),
	LanguageDescription.of({
		name: 'CSS',
		alias: ['scss', 'sass', 'less'],
		support: css()
	}),
	LanguageDescription.of({
		name: 'Python',
		alias: ['py'],
		support: python()
	}),
	LanguageDescription.of({
		name: 'SQL',
		alias: ['sqlite', 'postgres', 'mysql'],
		support: sql()
	}),
	LanguageDescription.of({
		name: 'YAML',
		alias: ['yml'],
		support: yaml()
	}),
	LanguageDescription.of({
		name: 'XML',
		alias: ['svg', 'plist'],
		support: xml()
	})
];

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
const livePreviewHideDecoration = Decoration.mark({ class: 'cm-live-hide' });
const listMarkerDecoration = Decoration.mark({ class: 'cm-list-marker' });

class ListMarkerWidget extends WidgetType {
	constructor(private marker: string) {
		super();
	}

	toDOM() {
		const span = document.createElement('span');
		span.className = 'cm-list-marker-widget';
		span.textContent = this.marker;
		return span;
	}
}

const markdownLinePlugin = ViewPlugin.fromClass(
	class {
		decorations = Decoration.none;
		private lastEmptyDecorationReport = 0;

		constructor(view: EditorView) {
			this.decorations = this.buildDecorations(view);
		}

		update(update: { docChanged: boolean; viewportChanged: boolean; view: EditorView }) {
			if (update.docChanged || update.viewportChanged) {
				this.decorations = this.buildDecorations(update.view);
			}
		}

		private buildDecorations(view: EditorView) {
			try {
				const builder = new RangeSetBuilder<Decoration>();
				const pending: Array<{ from: number; to: number; decoration: Decoration }> = [];
				const addDecoration = (from: number, to: number, decoration: Decoration) => {
					pending.push({ from, to, decoration });
				};
				const tree = syntaxTree(view.state);
				const doc = view.state.doc;
				const getLine = (number: number) =>
					number >= 1 && number <= doc.lines ? doc.line(number) : null;
				const codeBlockRanges: Array<{
					from: number;
					to: number;
					startLineFrom: number;
					endLineFrom: number;
				}> = [];
				const codeBlockRangeKeys = new Set<string>();
				const headingLevelsByLine = new Map<number, number>();
				const blockquoteDepthsByLine = new Map<number, number>();
				const listInfoByLine = new Map<number, { ordered: boolean; depth: number }>();
				const listMarkersByLine = new Map<number, { from: number; to: number; text: string }>();
				const taskMarkersByLine = new Map<number, { from: number; to: number; checked: boolean }>();
				const hrLines = new Set<number>();
				const imageByLine = new Map<number, { src: string; alt: string; title: string }>();
				const paragraphLines = new Set<number>();
				const tableRowLines = new Set<number>();
				const tableHeaderLines = new Set<number>();
				const tableDelimiterLines = new Set<number>();
				const blockquoteDecorations = new Map<string, Decoration>();
				const visibleFrom = view.visibleRanges[0]?.from ?? 0;
				const visibleTo = view.visibleRanges[view.visibleRanges.length - 1]?.to ?? 0;
				const getBlockquoteDecoration = (depth: number, isStart: boolean, isEnd: boolean) => {
					const key = `${depth}-${isStart ? 's' : 'm'}-${isEnd ? 'e' : 'm'}`;
					const cached = blockquoteDecorations.get(key);
					if (cached) {
						return cached;
					}

					let className = 'cm-blockquote';
					if (isStart) {
						className += ' cm-blockquote-start';
					}
					if (isEnd) {
						className += ' cm-blockquote-end';
					}

					const decoration = Decoration.line({
						attributes: {
							class: className,
							style: `--blockquote-depth: ${Math.max(depth, 1)}`
						}
					});
					blockquoteDecorations.set(key, decoration);
					return decoration;
				};
				const addLineRange = (from: number, to: number, handler: (lineNumber: number) => void) => {
					const startLine = doc.lineAt(from).number;
					const endLine = doc.lineAt(Math.max(to - 1, from)).number;
					for (let lineNumber = startLine; lineNumber <= endLine; lineNumber += 1) {
						handler(lineNumber);
					}
				};
				const getAncestorDepth = (node: { node: { parent: any; name: string } }, name: string) => {
					let depth = 0;
					let current = node.node;
					while (current) {
						if (current.name === name) {
							depth += 1;
						}
						current = current.parent;
					}
					return depth;
				};
				const findAncestorName = (
					node: { node: { parent: any; name: string } },
					names: string[]
				) => {
					let current = node.node.parent;
					while (current) {
						if (names.includes(current.name)) {
							return current.name;
						}
						current = current.parent;
					}
					return null;
				};
				const headingLevels: Record<string, number> = {
					ATXHeading1: 1,
					ATXHeading2: 2,
					ATXHeading3: 3,
					ATXHeading4: 4,
					ATXHeading5: 5,
					ATXHeading6: 6,
					SetextHeading1: 1,
					SetextHeading2: 2
				};
				const readLabelText = (from: number, to: number) => {
					const value = doc.sliceString(from, to);
					if (value.startsWith('[') && value.endsWith(']')) {
						return value.slice(1, -1);
					}
					return value;
				};
				const readTitleText = (from: number, to: number) => {
					const value = doc.sliceString(from, to);
					const first = value[0];
					const last = value[value.length - 1];
					if (first && last && first === last && (first === '"' || first === "'")) {
						return value.slice(1, -1);
					}
					return value;
				};
				const isQuoteOnlyLine = (text: string) => {
					const trimmed = text.trim();
					if (!trimmed) return false;
					for (const char of trimmed) {
						if (char !== '>') return false;
					}
					return true;
				};

				if (visibleTo > visibleFrom) {
					tree.iterate({
						from: visibleFrom,
						to: visibleTo,
						enter: (node) => {
							if (headingLevels[node.name]) {
								const lineNumber = doc.lineAt(node.from).number;
								headingLevelsByLine.set(lineNumber, headingLevels[node.name]);
								return;
							}

							if (node.name === 'HorizontalRule') {
								const lineNumber = doc.lineAt(node.from).number;
								hrLines.add(lineNumber);
								return;
							}

							if (node.name === 'Image') {
								const lineNumber = doc.lineAt(node.from).number;
								const imageNode = node.node;
								const labelNode = imageNode.getChild('LinkLabel');
								const urlNode = imageNode.getChild('URL');
								const titleNode = imageNode.getChild('LinkTitle');
								const alt = labelNode ? readLabelText(labelNode.from, labelNode.to) : '';
								const src = urlNode ? doc.sliceString(urlNode.from, urlNode.to) : '';
								const title = titleNode ? readTitleText(titleNode.from, titleNode.to) : '';
								if (src) {
									imageByLine.set(lineNumber, { src, alt, title });
								}
								return;
							}

							if (node.name === 'Paragraph') {
								addLineRange(node.from, node.to, (lineNumber) => {
									paragraphLines.add(lineNumber);
								});
								return;
							}

							if (node.name === 'Blockquote') {
								const depth = getAncestorDepth(node, 'Blockquote');
								addLineRange(node.from, node.to, (lineNumber) => {
									const current = blockquoteDepthsByLine.get(lineNumber) ?? 0;
									if (depth > current) {
										blockquoteDepthsByLine.set(lineNumber, depth);
									}
								});
								return;
							}

							if (node.name === 'ListItem') {
								const lineNumber = doc.lineAt(node.from).number;
								const depth = getAncestorDepth(node, 'ListItem');
								const listType = findAncestorName(node, ['OrderedList', 'BulletList']);
								listInfoByLine.set(lineNumber, {
									ordered: listType === 'OrderedList',
									depth
								});
								return;
							}

							if (node.name === 'ListMark') {
								const lineNumber = doc.lineAt(node.from).number;
								listMarkersByLine.set(lineNumber, {
									from: node.from,
									to: node.to,
									text: doc.sliceString(node.from, node.to)
								});
								return;
							}

							if (node.name === 'TaskMarker') {
								const lineNumber = doc.lineAt(node.from).number;
								const markerText = doc.sliceString(node.from, node.to);
								const checked = markerText.toLowerCase().includes('x');
								taskMarkersByLine.set(lineNumber, { from: node.from, to: node.to, checked });
								if (!listInfoByLine.has(lineNumber)) {
									const depth = getAncestorDepth(node, 'ListItem');
									const listType = findAncestorName(node, ['OrderedList', 'BulletList']);
									listInfoByLine.set(lineNumber, {
										ordered: listType === 'OrderedList',
										depth
									});
								}
								return;
							}

							if (node.name === 'TableRow') {
								const lineNumber = doc.lineAt(node.from).number;
								tableRowLines.add(lineNumber);
								return;
							}

							if (node.name === 'TableHeader') {
								const lineNumber = doc.lineAt(node.from).number;
								tableHeaderLines.add(lineNumber);
								return;
							}

							if (node.name === 'TableDelimiter') {
								const lineNumber = doc.lineAt(node.from).number;
								tableDelimiterLines.add(lineNumber);
								return;
							}

							if (node.name !== 'FencedCode' && node.name !== 'CodeBlock') {
								return;
							}

							const key = `${node.from}-${node.to}`;
							if (codeBlockRangeKeys.has(key)) {
								return false;
							}

							const startLine = doc.lineAt(node.from);
							const endLine = doc.lineAt(Math.max(node.to - 1, node.from));
							codeBlockRanges.push({
								from: node.from,
								to: node.to,
								startLineFrom: startLine.from,
								endLineFrom: endLine.from
							});
							codeBlockRangeKeys.add(key);
							return false;
						}
					});
				}

				codeBlockRanges.sort((left, right) => left.from - right.from);

				for (const { from, to } of view.visibleRanges) {
					let pos = from;
					let codeBlockIndex = 0;
					while (pos <= to) {
						const line = view.state.doc.lineAt(pos);
						const text = line.text;
						const lineNumber = line.number;
						while (
							codeBlockIndex < codeBlockRanges.length &&
							codeBlockRanges[codeBlockIndex].to < line.from
						) {
							codeBlockIndex += 1;
						}
						const codeBlock = codeBlockRanges[codeBlockIndex];
						const inCodeBlock = codeBlock && codeBlock.from <= line.to && codeBlock.to >= line.from;
						if (inCodeBlock) {
							if (line.from === codeBlock.startLineFrom) {
								addDecoration(line.from, line.from, codeBlockStartDecoration);
							} else if (line.from === codeBlock.endLineFrom) {
								addDecoration(line.from, line.from, codeBlockEndDecoration);
							} else {
								addDecoration(line.from, line.from, codeBlockDecoration);
							}
							pos = line.to + 1;
							continue;
						}

						const headingLevel = headingLevelsByLine.get(lineNumber);
						const listInfo = listInfoByLine.get(lineNumber) ?? null;
						const listMarker = listMarkersByLine.get(lineNumber) ?? null;
						const taskInfo = taskMarkersByLine.get(lineNumber) ?? null;
						const blockquoteDepth = blockquoteDepthsByLine.get(lineNumber) ?? 0;
						const isBlockquote = blockquoteDepth > 0;
						const isListItem = listInfo != null || taskInfo != null;
						const isHr = hrLines.has(lineNumber);
						const imageInfo = imageByLine.get(lineNumber) ?? null;
						const isImage = imageInfo != null;
						const isSeparator = tableDelimiterLines.has(lineNumber);
						const isRow = tableRowLines.has(lineNumber) || tableHeaderLines.has(lineNumber);
						const isTable = isRow || isSeparator;
						const isBlank = text.trim().length === 0 || (isBlockquote && isQuoteOnlyLine(text));
						const prevIsBlockquote = (blockquoteDepthsByLine.get(lineNumber - 1) ?? 0) > 0;
						const nextIsBlockquote = (blockquoteDepthsByLine.get(lineNumber + 1) ?? 0) > 0;
						const prevIsListItem =
							listInfoByLine.has(lineNumber - 1) || taskMarkersByLine.has(lineNumber - 1);
						const nextIsListItem =
							listInfoByLine.has(lineNumber + 1) || taskMarkersByLine.has(lineNumber + 1);
						const prevIsTableLine =
							tableRowLines.has(lineNumber - 1) ||
							tableHeaderLines.has(lineNumber - 1) ||
							tableDelimiterLines.has(lineNumber - 1);
						const nextIsTableLine =
							tableRowLines.has(lineNumber + 1) ||
							tableHeaderLines.has(lineNumber + 1) ||
							tableDelimiterLines.has(lineNumber + 1);
						const nextIsSeparator = tableDelimiterLines.has(lineNumber + 1);

						if (isBlockquote) {
							addDecoration(
								line.from,
								line.from,
								getBlockquoteDecoration(blockquoteDepth, !prevIsBlockquote, !nextIsBlockquote)
							);
						}

						if (isListItem) {
							// Calculate indent for both regular lists and task lists
							const markerText = listMarker?.text ?? '';
							const isOrdered =
								listInfo?.ordered ?? (markerText.trim().endsWith('.') ? true : false);
							if (isOrdered) {
								addDecoration(line.from, line.from, orderedListDecoration);
							} else if (listInfo) {
								addDecoration(line.from, line.from, unorderedListDecoration);
							}
							if ((listInfo?.depth ?? 0) > 1) {
								addDecoration(line.from, line.from, listNestedDecoration);
							}
							if (!prevIsListItem) {
								addDecoration(line.from, line.from, listStartDecoration);
							} else {
								addDecoration(line.from, line.from, listDecoration);
							}
							if (!nextIsListItem) {
								addDecoration(line.from, line.from, listEndDecoration);
							}
						}

						if (headingLevel) {
							const level = headingLevel;
							switch (level) {
								case 1:
									addDecoration(line.from, line.from, heading1Decoration);
									break;
								case 2:
									addDecoration(line.from, line.from, heading2Decoration);
									break;
								case 3:
									addDecoration(line.from, line.from, heading3Decoration);
									break;
								case 4:
									addDecoration(line.from, line.from, heading4Decoration);
									break;
								case 5:
									addDecoration(line.from, line.from, heading5Decoration);
									break;
								case 6:
									addDecoration(line.from, line.from, heading6Decoration);
									break;
								default:
									break;
							}
						}

						if (isHr) {
							addDecoration(line.from, line.from, hrDecoration);
						}

						if (isImage && imageInfo) {
							addDecoration(line.from, line.from, mediaDecoration);
							addDecoration(
								line.to,
								line.to,
								Decoration.widget({
									widget: new ImageWidget({
										src: imageInfo.src,
										alt: imageInfo.alt,
										title: imageInfo.title
									}),
									side: 1
								})
							);
						}

						if (isSeparator) {
							addDecoration(line.from, line.from, tableSeparatorDecoration);
						}

						if (isRow) {
							if (!prevIsTableLine) {
								addDecoration(line.from, line.from, tableStartDecoration);
							}
							if (nextIsSeparator) {
								addDecoration(line.from, line.from, tableHeaderDecoration);
							} else {
								let tableRowIndex = 0;
								let scanLineNumber = lineNumber - 1;
								while (scanLineNumber >= 1) {
									const scanLine = getLine(scanLineNumber);
									if (!scanLine) {
										break;
									}
									const scanLineIsTable =
										tableRowLines.has(scanLineNumber) ||
										tableHeaderLines.has(scanLineNumber) ||
										tableDelimiterLines.has(scanLineNumber);
									if (!scanLineIsTable) {
										break;
									}
									if (tableRowLines.has(scanLineNumber)) {
										tableRowIndex += 1;
									}
									scanLineNumber -= 1;
								}
								const decoration =
									tableRowIndex % 2 === 1 ? tableRowEvenDecoration : tableRowDecoration;
								addDecoration(line.from, line.from, decoration);
							}
							if (!nextIsTableLine) {
								addDecoration(line.from, line.from, tableEndDecoration);
							}
						}

						if (taskInfo) {
							addDecoration(
								line.from,
								line.from,
								taskInfo.checked ? taskCheckedDecoration : taskDecoration
							);
							const markerStart = listMarker?.from ?? taskInfo.from;
							const markerEnd = taskInfo.to;
							addDecoration(markerStart, markerEnd, listMarkerDecoration);
						} else if (listMarker) {
							const markerText = listMarker.text.trim();
							if (!markerText.endsWith('.')) {
								addDecoration(
									listMarker.from,
									listMarker.to,
									Decoration.replace({
										widget: new ListMarkerWidget('• '),
										side: 1
									})
								);
							}
						}

						if (isBlank) {
							addDecoration(line.from, line.from, blankLineDecoration);
						}

						if (
							!isBlank &&
							!headingLevel &&
							!isBlockquote &&
							!isListItem &&
							!taskInfo &&
							!isHr &&
							!isSeparator &&
							!isTable &&
							paragraphLines.has(lineNumber)
						) {
							addDecoration(line.from, line.from, paragraphDecoration);
						}

						pos = line.to + 1;
					}
				}
				const decorationCount = pending.length;
				pending.sort((left, right) => {
					if (left.from !== right.from) return left.from - right.from;
					const leftStart = (left.decoration as { startSide?: number }).startSide ?? 0;
					const rightStart = (right.decoration as { startSide?: number }).startSide ?? 0;
					if (leftStart !== rightStart) return leftStart - rightStart;
					if (left.to !== right.to) return left.to - right.to;
					const leftEnd = (left.decoration as { endSide?: number }).endSide ?? 0;
					const rightEnd = (right.decoration as { endSide?: number }).endSide ?? 0;
					return leftEnd - rightEnd;
				});
				for (const entry of pending) {
					builder.add(entry.from, entry.to, entry.decoration);
				}

				if (decorationCount === 0 && view.state.doc.length > 0 && view.visibleRanges.length > 0) {
					const now = Date.now();
					if (now - this.lastEmptyDecorationReport > 2000) {
						this.lastEmptyDecorationReport = now;
						this.reportDecorationIssue(view, 'decorations-empty', 'Line decorations missing', {
							docLength: view.state.doc.length
						});
					}
				}
				return builder.finish();
			} catch (error) {
				this.reportDecorationIssue(
					view,
					'decorations-error',
					'Decoration pipeline threw while building line decorations',
					{ error: this.serializeError(error) }
				);
				return this.decorations;
			}
		}

		private reportDecorationIssue(
			view: EditorView,
			type: string,
			message: string,
			details: Record<string, unknown> = {}
		) {
			const snapshot = this.captureViewportSnapshot(view);
			postToNative('jsError', {
				type,
				message,
				...details,
				snapshot
			});
		}

		private captureViewportSnapshot(view: EditorView) {
			const ranges = view.visibleRanges.map((range) => ({ from: range.from, to: range.to }));
			const selection = view.state.selection.main;
			const doc = view.state.doc;
			const samples: Array<{ line: number; from: number; to: number; text: string }> = [];
			const maxSamples = 6;
			for (const range of view.visibleRanges) {
				let pos = range.from;
				while (pos <= range.to && samples.length < maxSamples) {
					const line = doc.lineAt(pos);
					const text = line.text.length > 160 ? `${line.text.slice(0, 157)}...` : line.text;
					samples.push({ line: line.number, from: line.from, to: line.to, text });
					pos = line.to + 1;
				}
				if (samples.length >= maxSamples) {
					break;
				}
			}
			return {
				docLength: doc.length,
				selection: { from: selection.from, to: selection.to },
				visibleRanges: ranges,
				sampleLines: samples
			};
		}

		private serializeError(error: unknown) {
			if (error instanceof Error) {
				return { name: error.name, message: error.message, stack: error.stack };
			}
			return { message: String(error) };
		}
	},
	{
		decorations: (value) => value.decorations
	}
);

const livePreviewPlugin = ViewPlugin.fromClass(
	class {
		decorations = Decoration.none;
		private revealUntil = 0;
		private revealTimeout: number | null = null;

		constructor(view: EditorView) {
			this.decorations = this.buildDecorations(view);
		}

		update(update: {
			docChanged: boolean;
			viewportChanged: boolean;
			selectionSet: boolean;
			view: EditorView;
		}) {
			if (update.selectionSet) {
				this.scheduleReveal(update.view);
			}
			if (update.docChanged || update.viewportChanged || update.selectionSet) {
				this.decorations = this.buildDecorations(update.view);
			}
		}

		private scheduleReveal(view: EditorView) {
			this.revealUntil = Date.now() + 2000;
			if (this.revealTimeout) {
				window.clearTimeout(this.revealTimeout);
			}
			this.revealTimeout = window.setTimeout(() => {
				this.revealTimeout = null;
				view.dispatch({ annotations: Transaction.userEvent.of('live-preview') });
			}, 2000);
		}

		private buildDecorations(view: EditorView) {
			const builder = new RangeSetBuilder<Decoration>();
			const selection = view.state.selection;
			const tree = syntaxTree(view.state);
			const revealActive = Date.now() < this.revealUntil;
			const shouldRevealRange = (from: number, to: number) =>
				revealActive && selection.ranges.some((range) => range.from <= to && range.to >= from);
			const shouldRevealLine = (from: number) => {
				if (!revealActive) return false;
				const line = view.state.doc.lineAt(from);
				return selection.ranges.some((range) => range.from <= line.to && range.to >= line.from);
			};

			for (const { from, to } of view.visibleRanges) {
				tree.iterate({
					from,
					to,
					enter: (node) => {
						const name = node.name;
						if (name === 'HeaderMark') {
							if (!shouldRevealLine(node.from)) {
								addDecoration(node.from, node.to, livePreviewHideDecoration);
							}
							return;
						}
						if (name === 'EmphasisMark' || name === 'LinkMark' || name === 'CodeMark') {
							if (!shouldRevealRange(node.from, node.to)) {
								addDecoration(node.from, node.to, livePreviewHideDecoration);
							}
							return;
						}
						if (name === 'URL' || name === 'LinkTitle') {
							if (node.matchContext(['Link']) || node.matchContext(['Image'])) {
								let parent = node.node.parent;
								while (parent && parent.name !== 'Link' && parent.name !== 'Image') {
									parent = parent.parent;
								}
								const parentFrom = parent?.from ?? node.from;
								const parentTo = parent?.to ?? node.to;
								if (!shouldRevealRange(parentFrom, parentTo)) {
									addDecoration(node.from, node.to, livePreviewHideDecoration);
								}
							}
						}
					}
				});
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
			markdown({ extensions: [GFM, Autolink], addKeymap: true, codeLanguages }),
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
