import { fireEvent, render, screen } from '@testing-library/svelte';
import { describe, expect, it, vi } from 'vitest';

import type { TasksState } from '$lib/stores/tasks';
import TasksViewController from '$lib/components/tasks/TasksViewController.svelte';

const { createStubComponent } = vi.hoisted(() => ({
	createStubComponent:
		(testId: string) =>
		({ target }: { target: HTMLElement }) => {
			if (target) {
				const el = document.createElement('div');
				el.dataset.testid = testId;
				target.appendChild(el);
			}
			return {
				$set() {},
				$destroy() {}
			};
		}
}));

const { tasksStore, loadMock, clearConflictNoticeMock } = vi.hoisted(() => {
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
				subscribers.forEach((run) => run(value));
			},
			update(updater: (current: T) => T) {
				this.set(updater(value));
			}
		};
	};
	const baseState: TasksState = {
		selection: { type: 'today' },
		tasks: [],
		groups: [],
		projects: [],
		todayCount: 0,
		counts: {},
		syncNotice: '',
		conflictNotice: 'Tasks changed elsewhere. Refresh to continue.',
		isLoading: false,
		searchPending: false,
		newTaskDraft: null,
		newTaskSaving: false,
		newTaskError: '',
		error: ''
	};
	const state = createStore(baseState);
	const load = vi.fn();
	const clearConflictNotice = vi.fn(() =>
		state.update((current) => ({ ...current, conflictNotice: '' }))
	);
	return {
		tasksStore: {
			subscribe: state.subscribe,
			load,
			clearConflictNotice,
			cancelNewTask: vi.fn(),
			createTask: vi.fn(),
			clearNewTaskError: vi.fn(),
			renameTask: vi.fn(),
			updateNotes: vi.fn(),
			moveTask: vi.fn(),
			trashTask: vi.fn(),
			setDueDate: vi.fn(),
			completeTask: vi.fn()
		},
		loadMock: load,
		clearConflictNoticeMock: clearConflictNotice
	};
});

vi.mock('$lib/stores/tasks', () => ({
	tasksStore
}));

vi.mock('$lib/components/tasks/TasksTitlebar.svelte', () => ({
	default: createStubComponent('tasks-titlebar')
}));

vi.mock('$lib/components/tasks/TasksContent.svelte', () => ({
	default: createStubComponent('tasks-content')
}));

vi.mock('$lib/components/tasks/TaskDialogs.svelte', () => ({
	default: createStubComponent('task-dialogs')
}));

describe('TasksViewController', () => {
	it('shows conflict banner and refreshes on action', async () => {
		render(TasksViewController);

		expect(screen.getByText('Tasks changed elsewhere. Refresh to continue.')).toBeInTheDocument();

		const button = screen.getByRole('button', { name: 'Refresh tasks' });
		await fireEvent.click(button);

		expect(clearConflictNoticeMock).toHaveBeenCalled();
		expect(loadMock).toHaveBeenCalledWith({ type: 'today' }, { force: true, silent: true });
	});
});
