import { fireEvent, render, screen } from '@testing-library/svelte';
import { describe, expect, it, vi } from 'vitest';
import WebsiteRow from '$lib/components/websites/WebsiteRow.svelte';
import type { WebsiteItem } from '$lib/stores/websites';

const site: WebsiteItem = {
	id: 'site-1',
	title: 'Example Site',
	url: 'https://example.com/post',
	domain: 'example.com',
	saved_at: null,
	published_at: null,
	pinned: false,
	updated_at: null,
	last_opened_at: null
};

describe('WebsiteRow', () => {
	it('shows Copy Title in the context menu and calls its handler', async () => {
		const onCopyTitle = vi.fn();
		render(WebsiteRow, {
			site,
			isMenuOpen: true,
			archived: false,
			onOpen: vi.fn(),
			onOpenMenu: vi.fn(),
			onPin: vi.fn(),
			onRename: vi.fn(),
			onCopy: vi.fn(),
			onCopyTitle,
			onCopyUrl: vi.fn(),
			onDownload: vi.fn(),
			onArchive: vi.fn(),
			onDelete: vi.fn()
		});

		const copyTitleButton = screen.getByText('Copy Title');
		expect(copyTitleButton).toBeInTheDocument();
		await fireEvent.click(copyTitleButton);
		expect(onCopyTitle).toHaveBeenCalledWith(site);
	});
});
