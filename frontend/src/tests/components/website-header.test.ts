import { render, screen } from '@testing-library/svelte';
import { readFileSync } from 'node:fs';
import { describe, expect, it, vi } from 'vitest';
import WebsiteHeader from '$lib/components/websites/WebsiteHeader.svelte';
import type { WebsiteItem } from '$lib/stores/websites';

const { createStubComponent } = vi.hoisted(() => ({
	createStubComponent:
		() =>
		({ target }: { target: HTMLElement }) => {
			if (target) {
				const el = document.createElement('div');
				target.appendChild(el);
			}
			return { $set() {}, $destroy() {} };
		}
}));

vi.mock('$lib/components/ui/tooltip', () => ({
	Tooltip: createStubComponent(),
	TooltipTrigger: createStubComponent(),
	TooltipContent: createStubComponent()
}));

vi.mock('$lib/components/ui/popover/index.js', () => ({
	Root: createStubComponent(),
	Trigger: createStubComponent(),
	Content: createStubComponent()
}));

const longTitle =
	'A very long website title that should be visually truncated in the header when space is constrained';

const site: WebsiteItem = {
	id: 'site-1',
	title: longTitle,
	url: 'https://example.com/articles/really-long-path',
	domain: 'example.com',
	saved_at: null,
	published_at: null,
	pinned: false,
	updated_at: null,
	last_opened_at: null
};

describe('WebsiteHeader', () => {
	it('renders a title link with truncation styles and full-title tooltip text', () => {
		render(WebsiteHeader, {
			website: site,
			isCopied: false,
			onPinToggle: vi.fn(),
			onRename: vi.fn(),
			onCopy: vi.fn(),
			onCopyTitle: vi.fn(),
			onCopyUrl: vi.fn(),
			onDownload: vi.fn(),
			onArchive: vi.fn(),
			onDelete: vi.fn(),
			onClose: vi.fn()
		});

		const titleLink = screen.getByRole('link', { name: longTitle });
		expect(titleLink).toHaveClass('title-text');
		expect(titleLink).toHaveAttribute('title', longTitle);
	});

	it('keeps the title area shrinkable so long titles can truncate in the header', () => {
		const source = readFileSync('src/lib/components/websites/WebsiteHeader.svelte', 'utf8');
		expect(source).toMatch(/\.title-row\s*{[^}]*flex:\s*1;/s);
		expect(source).toMatch(/\.title-stack\s*{[^}]*flex:\s*1;/s);
		expect(source).toMatch(
			/\.title-text\s*{[^}]*display:\s*block;[^}]*text-overflow:\s*ellipsis;/s
		);
	});
});
