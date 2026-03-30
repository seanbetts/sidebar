import { render, screen } from '@testing-library/svelte';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import NotesPanel from '$lib/components/left-sidebar/NotesPanel.svelte';
import type { FileTreeState } from '$lib/types/file';

const { createNotesTree, createStubComponent, setTreeState, treeStore } = vi.hoisted(() => {
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

	const createNotesTree = (children: FileTreeState['trees'][string]['children']) => ({
		children,
		loading: false,
		expandedPaths: new Set<string>(),
		searchQuery: '',
		archivedLoading: false
	});

	const treeState = createStore<FileTreeState>({
		trees: {
			notes: createNotesTree([])
		}
	});

	return {
		createNotesTree,
		createStubComponent:
			() =>
			({ target }: { target: HTMLElement }) => {
				if (target) {
					const el = document.createElement('div');
					target.appendChild(el);
				}
				return { $set() {}, $destroy() {} };
			},
		setTreeState: treeState.set,
		treeStore: {
			subscribe: treeState.subscribe,
			toggleExpanded: vi.fn(),
			loadArchived: vi.fn()
		}
	};
});

vi.mock('$lib/stores/tree', () => ({
	treeStore
}));

vi.mock('$lib/hooks/useNoteActions', () => ({
	useNoteActions: () => ({
		updatePinnedOrder: vi.fn()
	})
}));

vi.mock('$lib/components/files/FileTreeNode.svelte', () => ({
	default: createStubComponent()
}));

describe('NotesPanel', () => {
	beforeEach(() => {
		setTreeState({
			trees: {
				notes: createNotesTree([])
			}
		});
		vi.clearAllMocks();
	});

	it('shows a true empty state without archive when nothing exists', () => {
		render(NotesPanel);

		expect(screen.getByText('No notes yet')).toBeInTheDocument();
		expect(screen.queryByText('Archive')).not.toBeInTheDocument();
	});

	it('shows archive and archived-only sparse state when only archived notes exist', () => {
		setTreeState({
			trees: {
				notes: createNotesTree([
					{
						name: 'Archive',
						path: 'notes/archive',
						type: 'directory',
						children: [
							{
								name: 'Archived.md',
								path: 'notes/archive/archived.md',
								type: 'file'
							}
						]
					}
				])
			}
		});

		render(NotesPanel);

		expect(screen.getByText('No notes yet')).toBeInTheDocument();
		expect(screen.getByText('Archive')).toBeInTheDocument();
		expect(screen.queryByText('No notes found')).not.toBeInTheDocument();
	});
});
