import { render, waitFor } from '@testing-library/svelte';
import { describe, expect, it, vi } from 'vitest';
import ChatMarkdown from '$lib/components/chat/ChatMarkdown.svelte';

const markdownConfigure = vi.fn();
const editorConstructor = vi.fn();

vi.mock('$lib/components/editor/tiptapLoader', async () => {
	const actual = await vi.importActual<typeof import('$lib/components/editor/tiptapLoader')>(
		'$lib/components/editor/tiptapLoader'
	);

	class MockEditor {
		public commands = {
			setContent: vi.fn()
		};

		constructor(options: unknown) {
			editorConstructor(options);
		}

		destroy() {}
	}

	return {
		...actual,
		loadTiptapModules: vi.fn(async () => ({
			Editor: MockEditor,
			StarterKit: { name: 'starter-kit' },
			ImageGallery: { name: 'image-gallery' },
			ImageWithCaption: { configure: vi.fn(() => ({ name: 'image-with-caption' })) },
			TaskList: { name: 'task-list' },
			TaskItem: { configure: vi.fn(() => ({ name: 'task-item' })) },
			TableKit: { name: 'table-kit' },
			Markdown: {
				name: 'markdown',
				configure: markdownConfigure
			}
		}))
	};
});

describe('ChatMarkdown', () => {
	it('does not enable raw HTML in markdown rendering', async () => {
		render(ChatMarkdown, {
			content: '<img src=x onerror=alert(1) />'
		});

		await waitFor(() => {
			expect(editorConstructor).toHaveBeenCalledTimes(1);
			expect(markdownConfigure).not.toHaveBeenCalled();
		});
	});
});
