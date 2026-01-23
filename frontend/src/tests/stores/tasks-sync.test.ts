import { describe, expect, it, vi, beforeEach } from 'vitest';
import { createTasksSyncCoordinator } from '$lib/stores/tasks-sync';
import type { Task, TaskArea, TaskProject } from '$lib/types/tasks';

vi.mock('$lib/services/task_sync', () => ({
	hydrateTaskCache: vi.fn().mockResolvedValue(null),
	flushTaskOutbox: vi.fn().mockResolvedValue(null)
}));

vi.mock('$lib/utils/cache', () => ({
	setCachedData: vi.fn()
}));

const createTask = (overrides: Partial<Task> = {}): Task => ({
	id: 'task-1',
	title: 'Test Task',
	status: 'open',
	deadline: null,
	notes: null,
	projectId: null,
	areaId: null,
	repeating: false,
	repeatTemplate: false,
	updatedAt: null,
	deletedAt: null,
	...overrides
});

const createArea = (overrides: Partial<TaskArea> = {}): TaskArea => ({
	id: 'area-1',
	title: 'Test Area',
	...overrides
});

const createProject = (overrides: Partial<TaskProject> = {}): TaskProject => ({
	id: 'proj-1',
	title: 'Test Project',
	areaId: null,
	...overrides
});

const createMockOptions = () => {
	let state = {
		selection: { type: 'today' as const },
		tasks: [] as Task[],
		areas: [] as TaskArea[],
		projects: [] as TaskProject[]
	};

	return {
		cacheTtl: 300000,
		cacheVersion: '1',
		isBrowser: false,
		tasksCacheKey: (selection: { type: string }) => `tasks.tasks.${selection.type}`,
		updateState: vi.fn((updater) => {
			state = updater(state);
		}),
		setMeta: vi.fn(),
		setSyncNotice: vi.fn(),
		setConflictNotice: vi.fn(),
		onNextTasks: vi.fn(),
		_getState: () => state,
		_setState: (newState: typeof state) => {
			state = newState;
		}
	};
};

describe('tasks-sync', () => {
	describe('createTasksSyncCoordinator', () => {
		let options: ReturnType<typeof createMockOptions>;

		beforeEach(() => {
			vi.clearAllMocks();
			options = createMockOptions();
		});

		describe('handleSyncResponse', () => {
			it('does nothing with null response', () => {
				const { handleSyncResponse } = createTasksSyncCoordinator(options);

				handleSyncResponse(null);

				expect(options.setConflictNotice).not.toHaveBeenCalled();
				expect(options.updateState).not.toHaveBeenCalled();
			});

			it('calls onNextTasks when response has nextTasks', () => {
				const { handleSyncResponse } = createTasksSyncCoordinator(options);
				const nextTasks = [createTask({ id: 'next-1' })];

				handleSyncResponse({ nextTasks });

				expect(options.onNextTasks).toHaveBeenCalledWith(nextTasks);
			});

			it('sets conflict notice when response has conflicts', () => {
				const { handleSyncResponse } = createTasksSyncCoordinator(options);

				handleSyncResponse({ conflicts: [{ id: 'task-1' }] });

				expect(options.setConflictNotice).toHaveBeenCalledWith(
					'Tasks changed elsewhere. Refresh to continue.'
				);
			});

			it('merges task updates into state', () => {
				options._setState({
					selection: { type: 'today' },
					tasks: [createTask({ id: 't1', title: 'Original' })],
					areas: [],
					projects: []
				});

				const { handleSyncResponse } = createTasksSyncCoordinator(options);

				handleSyncResponse({
					updates: {
						tasks: [createTask({ id: 't1', title: 'Updated' })]
					}
				});

				expect(options.updateState).toHaveBeenCalled();
			});

			it('merges area updates into state', () => {
				options._setState({
					selection: { type: 'today' },
					tasks: [],
					areas: [createArea({ id: 'a1', title: 'Original' })],
					projects: []
				});

				const { handleSyncResponse } = createTasksSyncCoordinator(options);

				handleSyncResponse({
					updates: {
						areas: [createArea({ id: 'a1', title: 'Updated' })]
					}
				});

				expect(options.updateState).toHaveBeenCalled();
				expect(options.setMeta).toHaveBeenCalled();
			});

			it('merges project updates into state', () => {
				options._setState({
					selection: { type: 'today' },
					tasks: [],
					areas: [],
					projects: [createProject({ id: 'p1', title: 'Original' })]
				});

				const { handleSyncResponse } = createTasksSyncCoordinator(options);

				handleSyncResponse({
					updates: {
						projects: [createProject({ id: 'p1', title: 'Updated' })]
					}
				});

				expect(options.updateState).toHaveBeenCalled();
				expect(options.setMeta).toHaveBeenCalled();
			});

			it('filters out deleted and completed tasks from updates', () => {
				options._setState({
					selection: { type: 'today' },
					tasks: [createTask({ id: 't1' }), createTask({ id: 't2' })],
					areas: [],
					projects: []
				});

				const { handleSyncResponse } = createTasksSyncCoordinator(options);

				handleSyncResponse({
					updates: {
						tasks: [
							createTask({ id: 't1', status: 'completed' }),
							createTask({ id: 't2', deletedAt: '2026-01-01' })
						]
					}
				});

				expect(options.updateState).toHaveBeenCalled();
				const updater = options.updateState.mock.calls[0][0];
				const result = updater({
					selection: { type: 'today' },
					tasks: [createTask({ id: 't1' }), createTask({ id: 't2' })],
					areas: [],
					projects: []
				});
				expect(result.tasks).toHaveLength(0);
			});

			it('does nothing when updates are empty', () => {
				const { handleSyncResponse } = createTasksSyncCoordinator(options);

				handleSyncResponse({ updates: {} });

				expect(options.updateState).not.toHaveBeenCalled();
			});
		});

		describe('initialize', () => {
			it('does nothing when not in browser', () => {
				options.isBrowser = false;

				const { initialize } = createTasksSyncCoordinator(options);
				initialize();

				expect(options.updateState).not.toHaveBeenCalled();
			});

			it('only initializes once', () => {
				options.isBrowser = true;
				// Mock window for browser environment
				vi.stubGlobal('window', { addEventListener: vi.fn() });

				const { initialize } = createTasksSyncCoordinator(options);
				initialize();
				initialize();
				initialize();

				expect(window.addEventListener).toHaveBeenCalledTimes(1);

				vi.unstubAllGlobals();
			});
		});
	});
});
