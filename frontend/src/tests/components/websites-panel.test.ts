import { render, screen } from '@testing-library/svelte';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import WebsitesPanel from '$lib/components/websites/WebsitesPanel.svelte';

const { createStubComponent, setWebsitesState, websitesStore } = vi.hoisted(() => {
	const createStore = <T>(initial: T) => {
		let value = initial;
		const subscribers = new Set<(next: T) => void>();
		return {
			subscribe(run: (next: T) => void) {
				run(value);
				subscribers.add(run);
				return () => subscribers.delete(run);
			},
			set(next: T) {
				value = next;
				subscribers.forEach((fn) => fn(value));
			}
		};
	};

	const websitesState = createStore({
		error: null as string | null,
		loading: false,
		items: [] as Array<Record<string, unknown>>,
		searchQuery: '',
		pendingWebsite: null as Record<string, unknown> | null,
		archivedLoading: false
	});

	return {
		createStubComponent:
			(testId: string) =>
			({ target }: { target: HTMLElement }) => {
				if (target) {
					const el = document.createElement('div');
					el.dataset.testid = testId;
					target.appendChild(el);
				}
				return { $set() {}, $destroy() {} };
			},
		setWebsitesState: websitesState.set,
		websitesStore: {
			subscribe: websitesState.subscribe,
			loadArchived: vi.fn(),
			refreshItem: vi.fn()
		}
	};
});

vi.mock('$lib/stores/websites', () => ({
	websitesStore
}));

vi.mock('$lib/hooks/useWebsiteActions', () => ({
	useWebsiteActions: () => ({
		openWebsite: vi.fn(),
		renameWebsite: vi.fn(),
		pinWebsite: vi.fn(),
		archiveWebsite: vi.fn(),
		deleteWebsite: vi.fn(),
		updatePinnedOrder: vi.fn()
	})
}));

vi.mock('$lib/components/websites/WebsiteRow.svelte', () => ({
	default: createStubComponent('website-row')
}));

vi.mock('$lib/components/files/DeleteDialogController.svelte', () => ({
	default: createStubComponent('delete-dialog')
}));

describe('WebsitesPanel', () => {
	beforeEach(() => {
		setWebsitesState({
			error: null,
			loading: false,
			items: [],
			searchQuery: '',
			pendingWebsite: null,
			archivedLoading: false
		});
		vi.clearAllMocks();
	});

	it('shows global empty state when no websites exist', () => {
		render(WebsitesPanel);
		expect(screen.getByText('No websites yet')).toBeInTheDocument();
	});

	it('hides non-archived websites empty block when only archived websites exist', () => {
		setWebsitesState({
			error: null,
			loading: false,
			items: [
				{
					id: 'arch-1',
					title: 'Archived Site',
					url: 'https://example.com',
					pinned: false,
					archived: true
				}
			],
			searchQuery: '',
			pendingWebsite: null,
			archivedLoading: false
		});

		render(WebsitesPanel);
		expect(screen.queryByText('No websites saved')).not.toBeInTheDocument();
		expect(screen.getByText('Archive')).toBeInTheDocument();
	});
});
