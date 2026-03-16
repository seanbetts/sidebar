import type { Editor } from '@tiptap/core';

export interface TiptapRuntimeModules {
	Editor: typeof import('@tiptap/core').Editor;
	StarterKit: typeof import('@tiptap/starter-kit').default;
	ImageGallery: typeof import('$lib/components/editor/ImageGallery').ImageGallery;
	ImageWithCaption: typeof import('$lib/components/editor/ImageWithCaption').ImageWithCaption;
	TaskList: typeof import('@tiptap/extension-list').TaskList;
	TaskItem: typeof import('@tiptap/extension-list').TaskItem;
	TableKit: typeof import('@tiptap/extension-table').TableKit;
	Markdown: typeof import('tiptap-markdown').Markdown;
}

let tiptapModulesPromise: Promise<TiptapRuntimeModules> | null = null;
let textSelectionPromise: Promise<typeof import('@tiptap/pm/state').TextSelection> | null = null;

/**
 * Load the shared Tiptap runtime modules only when an editor or renderer is actually needed.
 */
export function loadTiptapModules(): Promise<TiptapRuntimeModules> {
	if (!tiptapModulesPromise) {
		tiptapModulesPromise = Promise.all([
			import('@tiptap/core'),
			import('@tiptap/starter-kit'),
			import('$lib/components/editor/ImageGallery'),
			import('$lib/components/editor/ImageWithCaption'),
			import('@tiptap/extension-list'),
			import('@tiptap/extension-table'),
			import('tiptap-markdown')
		]).then(
			([core, starterKit, imageGallery, imageWithCaption, listExtensions, tableKit, markdown]) => ({
				Editor: core.Editor,
				StarterKit: starterKit.default,
				ImageGallery: imageGallery.ImageGallery,
				ImageWithCaption: imageWithCaption.ImageWithCaption,
				TaskList: listExtensions.TaskList,
				TaskItem: listExtensions.TaskItem,
				TableKit: tableKit.TableKit,
				Markdown: markdown.Markdown
			})
		);
	}

	return tiptapModulesPromise;
}

/**
 * Load ProseMirror selection helpers only when cursor restoration is required.
 */
export function loadTextSelection(): Promise<typeof import('@tiptap/pm/state').TextSelection> {
	if (!textSelectionPromise) {
		textSelectionPromise = import('@tiptap/pm/state').then((module) => module.TextSelection);
	}

	return textSelectionPromise;
}

/**
 * Build the shared markdown extension stack for editors and read-only viewers.
 *
 * @param modules Runtime-loaded Tiptap modules.
 * @param options Optional markdown configuration.
 * @returns Extension list passed to the editor constructor.
 */
export function createMarkdownExtensions(
	modules: TiptapRuntimeModules,
	options: { enableHtml?: boolean } = {}
) {
	const markdownExtension =
		options.enableHtml === true ? modules.Markdown.configure({ html: true }) : modules.Markdown;

	return [
		modules.StarterKit,
		modules.ImageGallery,
		modules.ImageWithCaption.configure({ inline: false, allowBase64: true }),
		modules.TaskList,
		modules.TaskItem.configure({ nested: true }),
		modules.TableKit,
		markdownExtension
	];
}

/**
 * Read markdown content from a Tiptap editor instance.
 *
 * @param editor Editor instance with markdown storage.
 * @returns Markdown representation of the current document.
 */
export function getEditorMarkdown(editor: Editor): string {
	return (
		editor as Editor & { storage: { markdown: { getMarkdown: () => string } } }
	).storage.markdown.getMarkdown();
}
